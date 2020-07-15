# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    AllowedHosts = {}
    GlobChars = /[\*\{\[]/
    HostGET = {}
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert

    def self.action_icon action, fetched=true
      case action
      when 'HEAD'
        '🗣'
      when 'OPTIONS'
        '🔧'
      when 'POST'
        '📝'
      when 'GET'
        fetched ? '🐕' : ' '
      else
        action
      end
    end

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      AllowedHosts.has_key?(host) || HostGET.has_key?(host) || ENV.has_key?('COOKIES')
    end

    def allowedOrigin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def cacheResponse
      return fileResponse if StaticFormats.member?(ext.downcase) && node.file? # direct node
      nodes = nodeSet                                                          # indirect nodes
      if nodes.size == 1 && (StaticFormats.member?(nodes[0].ext) || (selectFormat == 'text/turtle' && nodes[0].ext == 'ttl'))
        nodes[0].fileResponse           # nothing to merge or transform
      else                              # transform and/or merge nodes
        nodes = nodes.map &:summary if env[:summary] # summarize nodes
        nodes.map &:loadRDF             # node(s) -> Graph
        timeMeta                        # reference temporally-adjacent nodes
        graphResponse                   # HTTP Response
      end
    end

    def cacheURL
      return self unless h = host || env['SERVER_NAME']
      return self if h == 'localhost'
      ['http://localhost:8000/', h, path, (query ? ['?',query] : nil), (fragment ? ['#', fragment] : nil) ].join
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']           # allow HTTP methods
      uri = RDF::URI('http' + (env['SERVER_NAME'] == 'localhost' ? '' : 's') + '://' + env['HTTP_HOST']).join env['REQUEST_PATH'] # resource identifier
      uri.query = env['QUERY_STRING'].sub(/^&/,'').gsub(/&&+/,'&') if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # strip leading + consecutive & from qs so URI library doesn't freak out
      resource = uri.R env                                                      # bind resource and environment
      env[:base] = resource                                                     # base URI
      env[:refhost] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}; env[:feeds] = []; env[:links] = {}                       # response-header storage
      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch request
        format = resource.format_icon head['Content-Type']                      # log response
        color = env[:deny] ? '31;1' : (format_color format)
        unless [204, 304].member? status
          puts [env[:deny] ? '🛑' : (action_icon env['REQUEST_METHOD'], env[:fetched]),
                (status_icon status),
                format,
                env[:repository] ? (env[:repository].size.to_s + '⋮') : nil,
                env[:refhost] ? ["\e[#{color}m", env[:refhost], "\e[0m→"] : nil,
                "\e[#{color}#{env[:refhost] != resource.host ? ';7' : ''}m",
                resource.uri, "\e[0m",
                head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil,
                env['HTTP_ACCEPT']
               ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '
        end
        [status, head, body]}                                                   # response
    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts "\e[7;31m500\e[0m " + msg , trace
      [500, {'Content-Type' => 'text/html'}, env['REQUEST_METHOD'] == 'HEAD' ? [] : ['<html><body style="background-color: red; font-size: 12ex; text-align: center">500</body></html>']]
    end

    def HTTP.decompress head, body
      case (head['content-encoding']||head['Content-Encoding']).to_s
      when /^br(otli)?$/i
        Brotli.inflate body
      when /gzip/i
        (Zlib::GzipReader.new StringIO.new body).read
      when /flate|zip/i
        Zlib::Inflate.inflate body
      else
        body
      end
    rescue Exception => e
      puts [e.class, e.message].join " "
      ''
    end
 
    def deny status=200, type=nil
      env[:deny] = true
      type, content = if type == :stylesheet || ext == 'css'
                        ['text/css', '']
                      elsif type == :font || %w(eot otf ttf woff woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(bmp gif png).member?(ext)
                        ['image/png', SiteIcon]
                      elsif type == :script || ext == 'js'
                        ['application/javascript', '//']
                      elsif type == :JSON || ext == 'json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 1.5em, #f00 1.5em, #f00 8em); text-align: center'><span style='color: #fff; font-size: 22em; font-weight: bold; text-decoration: none'>⌘</span></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      env[:deny] = true
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    # if needed, return lazily-generated entity, via Rack handler if file-reference
    def entity generator = nil
      if env['HTTP_IF_NONE_MATCH']&.strip&.split(/\s*,\s*/)&.include? env[:resp]['ETag']
        [304, {}, []]                            # unmodified entity
      else
        body = generator ? generator.call : self # generate entity
        if body.class == WebResource             # file-reference?
          Rack::Files.new('.').serving(Rack::Request.new(env), body.fsPath).yield_self{|s,h,b|
            if 304 == s
              [304, {}, []]                      # unmodified file
            else
              if h['Content-Type'] == 'application/javascript'
                h['Content-Type'] = 'application/javascript; charset=utf-8' # add charset tag
              elsif RDF::Format.file_extensions.has_key? body.ext.to_sym # format via path extension
                h['Content-Type'] = RDF::Format.file_extensions[body.ext.to_sym][0].content_type[0]
              end
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]       # file
            end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [200, env[:resp], [body]]              # inline data
        end
      end
    end

    def env e = nil
      if e
        @env = e;  self
      else
        @env ||= {}
      end
    end

    # fetch from cache or remote server
    def fetch
      if StaticFormats.member? ext.downcase                                                  # static representation valid in cache if exists:
        return [304,{},[]] if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has resource in browser-cache
        return fileResponse if node.file?                                                    #  server has static node on file
      end
      nodes = nodeSet
      return nodes[0].fileResponse if nodes.size == 1 && StaticFormats.member?(nodes[0].ext) #  server has single static-node in mapped node-set
      fetchHTTP                                                                 # fetch via HTTPS
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      ['http://', host, path, query ? ['?', query] : nil].join.R(env).fetchHTTP # fetch via HTTP
    end

    # fetch from remote                               OPTIONS
    def fetchHTTP cache: !ENV.has_key?('NOCACHE'),   # cache representation and mapped RDF graph(s)
                  response: true,                    # construct HTTP response
                  transform: (query_values||{}).has_key?('rdf'), # definitely transform
                  transformable: true                # allow format transforms
      transformable = false if (query_values||{})['UI'] == 'upstream'

      URI.open(uri, headers.merge({redirect: false})) do |response| ; env[:fetched] = true
        h = response.meta                            # upstream metadata
        if response.status.to_s.match? /206/         # partial response
          h['Access-Control-Allow-Origin'] = allowedOrigin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                  # return part
        else
          format = if path == '/feed' || (query_values||{})['mime'] == 'xml'
                     'application/atom+xml'          # Atom/RSS content-type
                   elsif h.has_key? 'content-type'
                     h['content-type'].split(/;/)[0] # content-type in HTTP header
                   elsif RDF::Format.file_extensions.has_key? ext.to_sym # path extension
                     RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
                   end
          formatExt = Suffixes[format] || Suffixes_Rack[format] # format-suffix
          body = HTTP.decompress h, response.read                     # read body
          if format && reader = RDF::Reader.for(content_type: format) # read RDF from body
            reader.new(body, base_uri: self){|_| (env[:repository] ||= RDF::Repository.new) << _ }
          end
          if cache
            c = fsPath.R                             # cache URI
            c += querySlug                           # append query-hash
            c += formatExt if formatExt && c.R.extension != formatExt # affix format-suffix
            c.R.writeFile body                       # cache representation
            saveRDF                                  # cache RDF graph(s)
          end
          return unless response                                                           # HTTP response:
          %w(Access-Control-Allow-Origin
             Access-Control-Allow-Credentials
             Content-Type ETag).map{|k| env[:resp][k] ||= h[k.downcase] if h[k.downcase]}  # misc upstream headers
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin                      # CORS header
          env[:resp]['Set-Cookie'] ||= h['set-cookie'] if h['set-cookie'] && allowCookies? # Set-Cookie header
          h['link'] && h['link'].split(',').map{|link|                                     # Link header - parse and merge
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}
          if transform || (transformable && format && (format.match?(/atom|html|rss|turtle|xml/i) && !format.match?(/dash.xml/))) # transform resource
            graphResponse                                               # locally-generated doc
          else
            if format == 'text/html'                                    # upstream HTML
              doc = Webize::HTML.clean body, self, false                # clean upstream doc
              Webize::HTML.cacherefs doc, env, false if env[:cacherefs] # content location
              body = doc.to_html
            end
            env[:resp]['Content-Length'] = body.bytesize.to_s           # Content-Length header
            [200, env[:resp], [body]]                                   # upstream doc
          end
        end
      end
    rescue Exception => e
      status = e.respond_to?(:io) ? e.io.status[0] : ''
      case status
      when /30[12378]/ # redirect
        dest = (join e.io.meta['location']).R env
        if scheme == 'https' && dest.scheme == 'http'
          puts "WARNING HTTPS downgraded to HTTP: #{uri} -> #{dest}"
          dest.fetchHTTP
        else
          [302, {'Location' => dest.href}, []]
        end
      when /304/ # Not Modified
        [304, {}, []]
      when /4\d\d/ # Not Found/Allowed
        cacheResponse
      when /300|5\d\d/ # upstream multiple choices or server error
        [status.to_i, (headers e.io.meta), [e.io.read]]
      else
        raise
      end
    end

    def self.format_color format_icon
      case format_icon
      when '➡️'
        '38;5;7'
      when '📃'
        '34;1'
      when '📜'
        '36;1'
      when '🗒'
        '38;5;128'
      when '🐢'
        '32;1'
      when '🎨'
        '38;5;227'
      when '🖼️'
        '38;5;226'
      when '🎬'
        '38;5;208'
      else
        '35;1'
      end
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      return [204,{},[]] if path.match? /gen(erate)?_?204$/ # connectivity-check
      unless path == '/'                                    # container reference
        up = File.dirname path
        up += '/' unless up == '/'
        up += '?' + query if query
        env[:links][:up] = up
      end
      if localNode?
        env[:cacherefs] = true
        p = parts[0]
        if %w{m d h}.member? p                 # timeline redirect
          dateDir
        elsif p == 'favicon.ico'
          SiteDir.join('favicon.ico').R(env).fileResponse
        elsif !p || p.match?(/^(\d\d\d\d|msg)$/) || node.file?
          cacheResponse                        # local node
        else
          (env[:base] = remoteURL).hostHandler # remote node
        end
      else
        hostHandler
      end
    end

    def hostHandler
      if handler = HostGET[host]               # host handler
        handler[self]
      elsif gunk?                              # gunk handler
        if gunkQuery?
          [301, {'Location' => ['//', host, path].join.R(env).href}, []]
        else
          deny
        end
      else                                     # fetch remote
        fetch
      end
    end

    alias_method :get, :fetch

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # return header
    end

    # headers cleaned/filtered for export
    def headers raw = nil
      raw ||= env || {} # raw headers
      head = {}         # clean headers
      raw.map{|k,v|     # inspect headers
        k = k.to_s
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix, tokenize
          if %w{cl dfe id spf utc xsrf}.member? t # acronym?
            t = t.upcase                          # upcase
          else
            t[0] = t[0].upcase                    # capitalize
          end
          t                                       # token
        }.join(k.match?(/(_AP_|PASS_SFP)/i) ? '_' : '-') # join tokens
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless %w(base cacherefs colors connection downloadable feeds fetched graph host images keep-alive links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rack.tempfiles rdf refhost remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software summary sort te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for).member?(key.downcase)} # external multi-hop headers

      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless (head['Accept']||'').match?(/text\/turtle/) # accept Turtle

      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
      end

      case host
      when /wsj\.com$/
        head['Referer'] = 'http://drudgereport.com/'
      when /youtube.com$/
        head['Referer'] = 'https://www.youtube.com/'
      end

      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st' # we want redirection in HTTP, not Javascript,
      head.delete 'User-Agent' if host == 't.co'            # so don't advertise a JS-capable user-agent

      head
    end

    def href
      env[:cacherefs] ? cacheURL : uri
    end

    def notfound; [404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def OPTIONS
      if AllowedHosts.has_key? host
        self.OPTIONSthru
      else
        env[:deny] = true
        [204, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => AllowedHeaders,
               'Access-Control-Allow-Origin' => allowedOrigin},
         []]
      end
    end

    def OPTIONSthru
      r = HTTParty.options uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    def POST
      (ENV.has_key?('POST') || AllowedHosts.has_key?(host) || host.match?(/\.ttvnw.net$/)) && !path.match?(/\/jot\//) && self.POSTthru || denyPOST
    end

    def POSTthru
      head = headers
      body = env['rack.input'].read
      env.delete 'rack.input'
      r = HTTParty.post uri, headers: head, body: body
      head = headers r.headers
      [r.code, head, [r.body]]
    end

    def PUT
      if AllowedHosts.has_key? host
        self.PUTthru
      else
        env[:deny] = true
        [204, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => AllowedHeaders,
               'Access-Control-Allow-Origin' => allowedOrigin},
         []]
      end
    end

    def PUTthru
      r = HTTParty.put uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' if !h || h.empty?
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def remoteURL
      ['https:/' , path.sub(/^\/https?:\//,''),
       (query ? ['?', query] : nil),
       (fragment ? ['#', fragment] : nil) ].join.R env
    end

    def selectFormat default = 'text/html'
      return default unless env && env.has_key?('HTTP_ACCEPT') # default via no specification

      index = {} # q -> format map
      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats sorted on descending q-value
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with 🐢-winner
          return default if f == '*/*'                        # default via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF via writer definition
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF via writer definition

      default                                                 # default
    end

    def self.status_icon status
      {202 => '➕',
       204 => '✅',
       301 => '➡️',
       302 => '➡️',
       303 => '➡️',
       304 => '✅',
       401 => '🚫',
       403 => '🚫',
       404 => '❓',
       410 => '❌',
       500 => '🚩'}[status] || (status == 200 ? nil : status)
    end

  end
  include HTTP
end
