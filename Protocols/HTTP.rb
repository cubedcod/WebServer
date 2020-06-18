# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    AllowedHosts = {}
    CookieHosts = {}
    GlobChars = /[\*\{\[]/
    HostGET = {}
    Methods = %w(GET HEAD OPTIONS POST PUT)
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert
    SingleHop = %w(cacherefs connection fetch gunk host keep-alive links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rack.tempfiles rdf refhost remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software summary sort te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests ux version via x-forwarded-for)

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      AllowedHosts.has_key?(host) || CookieHosts.has_key?(host) || CookieHost.match?(host) || ENV.has_key?('COOKIES')
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

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']           # allow HTTP methods
      URIs.gunkTree true if GunkFile.mtime > GunkHosts[:mtime]                  # check for config changes

      uri = RDF::URI('https://' + env['HTTP_HOST']).join env['REQUEST_PATH']    # resource identifier
      uri.query = env['QUERY_STRING'].sub(/^&/,'').gsub(/&&+/,'&') if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # strip leading + consecutive & from qs so URI library doesn't freak out
      resource = uri.R env                                                      # request resource and environment

      env[:refhost] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}                                                           # response-header storage
      env[:links] = {}                                                          # response-header links

      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch request
        ext = resource.path ? resource.ext.downcase : ''                        # log response
        mime = head['Content-Type'] || ''

        action_icon = if env[:deny]
                        '🛑'
                      else
                        case env['REQUEST_METHOD']
                        when 'HEAD'
                          '🗣'
                        when 'OPTIONS'
                          '🔧'
                        when 'POST'
                          '📝'
                        when 'GET'
                          env[:fetch] ? '🐕' : ' '
                        else
                          env['REQUEST_METHOD']
                        end
                      end

        status_icon = {202 => '➕',
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

        format_icon = if ext == 'css' || mime.match?(/text\/css/)
                        '🎨'
                      elsif ext == 'js' || mime.match?(/script/)
                        '📜'
                      elsif ext == 'json' || mime.match?(/json/)
                        '🗒'
                      elsif %w(gif jpeg jpg png svg webp).member?(ext) || mime.match?(/^image/)
                        '🖼️'
                      elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
                        '🔉'
                      elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
                        '🎬'
                      elsif ext == 'txt' || mime.match?(/text\/plain/)
                        '🇹'
                      elsif ext == 'ttl' || mime.match?(/text\/turtle/)
                        '🐢'
                      elsif %w(htm html).member?(ext) || mime.match?(/html/)
                        '📃'
                      elsif mime.match? /^(application\/)?font/
                        '🇦'
                      elsif mime.match? /octet.stream/
                        '🧱'
                      else
                        mime
                      end

        color = if env[:deny]
                  '31;1'
                else
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

        triple_count = env[:repository] ? (env[:repository].size.to_s + '⋮') : nil
        thirdparty = env[:refhost] != resource.host

        unless [204, 304].member? status
          puts [action_icon, status_icon, format_icon, triple_count,
                env[:refhost] ? ["\e[#{color}m", env[:refhost], "\e[0m→"] : nil,
                "\e[#{color}#{thirdparty ? ';7' : ''}m", env[:cacherefs] ? resource.remoteURL : resource.uri, "\e[0m",
                head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil, env['HTTP_ACCEPT']
               ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '
        end

        [status, head, body]} # response
    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts "\e[7;31m500\e[0m " + msg , trace
      [500, {'Content-Type' => 'text/html'},
       env['REQUEST_METHOD'] == 'HEAD' ? [] : [uri.R(env).htmlDocument(
                                                 {uri => {Content => [
                                                            {_: :h3, c: msg.hrefs, style: 'color: red'},
                                                            {_: :pre, c: trace.hrefs},
                                                            (HTML.keyval (Webize::HTML.webizeHash env), env),
                                                            (HTML.keyval (Webize::HTML.webizeHash e.io.meta), env if e.respond_to? :io)]}})]]
    end

    def self.Cookies host
      CookieHosts[host] = true
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
                        q = query_values || {}
                        q['allow'] = ServerKey
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{HTTP.qs q}' style='color: #fff; font-size: 22em; font-weight: bold; text-decoration: none'>⌘</a></body></html>"]
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

    def env e = nil
      if e
        @env = e;  self
      else
        @env ||= {}
      end
    end

    # fetch node from cache or remote
    def fetch options = nil ; options ||= {}
      return nodeResponse if ENV.has_key?('OFFLINE')                                                     # offline, return cached nodes
      if StaticFormats.member? ext.downcase
        return [304,{},[]] if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client cache-hit
        return fileResponse if node.file?                                                                # server cache-hit - direct
      end
      nodes = nodeSet
      return nodes[0].fileResponse if nodes.size == 1 && StaticFormats.member?(nodes[0].ext)             # server cache-hit - indirect

      loc = ['//',host,(port ? [':',port] : nil),path,options[:suffix],(query ? ['?',query] : nil)].join # locator
      ('https:' + loc).R(env).fetchHTTP options                                                          # HTTPS fetch
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      ('http:' + loc).R(env).fetchHTTP options                                                           # fallback HTTP fetch
    end

    def fetchHTTP options = {}; env[:fetch] = true
      URI.open(uri, headers.merge({redirect: false})) do |response|
        h = response.meta                                     # upstream metadata
        if response.status.to_s.match? /206/                  # partial response
          h['Access-Control-Allow-Origin'] = allowedOrigin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                           # return part
        else
          format = if path=='/feed' || (query_values||{})['mime']=='xml'
                     'application/atom+xml'                   # Atom/RSS content-type
                   elsif h.has_key? 'content-type'
                     h['content-type'].split(/;/)[0]          # content-type in HTTP header
                   elsif RDF::Format.file_extensions.has_key? ext.to_sym # path extension
                     RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
                   end
          formatExt = Suffixes[format] || Suffixes_Rack[format] # format -> name-suffix
          puts "WARNING format undefined for URL #{uri}, please fix your server" unless format

          body = HTTP.decompress h, response.read             # decompress body
          body = Webize::HTML.clean body, self if format == 'text/html' # clean HTML
         
          cache = fsPath.R                                    # base path for cache
          cache += querySlug                                  # add qs-derived slug
          if formatExt
            cache += formatExt unless cache.R.extension == formatExt  # append format-suffix
          else
            puts "WARNING suffix undefined for format #{format}, please add to Formats/MIME.rb" if format
          end
          cache.R.writeFile body                              # cache representation

          reader = RDF::Reader.for content_type: format       # find RDF reader
          reader.new(body, base_uri: self){|_|(env[:repository] ||= RDF::Repository.new) << _ } if reader && !NoScan.member?(formatExt)
          return self if options[:intermediate]               # intermediate fetch, no immediate indexing and response
          saveRDF if reader                                   # index RDF
                                                              # add upstream metadata to response
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k| env[:resp][k] ||= h[k.downcase] if h[k.downcase]}
          h['link'].split(',').map{|link|                     # parse Link metadata
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end} if h['link']
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
          env[:resp]['Set-Cookie'] ||= h['set-cookie'] if h['set-cookie'] && allowCookies?
          if !options[:reformat] && fixedFormat?(format)
            env[:resp]['Content-Length'] = body.bytesize.to_s # content size
            [200, env[:resp], [body]]                         # upstream document
          else
            graphResponse                                     # locally-generated document
          end
        end
      end
    rescue Exception => e
      status = e.respond_to?(:io) ? e.io.status[0] : ''
      case status
      when /30[12378]/ # redirect
        dest = e.io.meta['location'].R env
        if scheme == 'https' && dest.scheme == 'http'
          puts "WARNING HTTPS downgraded to HTTP: #{uri} -> #{dest}"
          dest.fetchHTTP options
        else
          [302, {'Location' => dest.uri}, []]
        end
      when /304/ # Not Modified
        [304, {}, []]
      when /404/ # Not Found
        env[:status] = 404
        upstreamUI? ? [404, (headers e.io.meta), [e.io.read]] : nodeResponse
      when /300|4(0[13]|10|29)|50[03]|999/
        [status.to_i, (headers e.io.meta), [e.io.read]]
      else
        raise
      end
    end

    def fixedFormat? format
      return true if !format || upstreamUI? || format.match?(/dash.xml/)                               # unknown or upstream format
      return false if (query_values||{}).has_key?('rdf') || format.match?(/atom|html|rss|turtle|xml/i) # default or requested transformability
      return true
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      return [204,{},[]] if path.match? /gen(erate)?_?204$/ # connectivity-check response
      unless path == '/'                                    # point to containing node
        up = File.dirname path
        up += '/' unless up == '/'
        up += '?' + query if query
        env[:links][:up] = up
      end
      if localNode?
        if %w{m d h}.member? parts[0]                       # timeline redirect
          dateDir
        elsif parts[0] == 'cache'
          env[:cacherefs] = true
          remoteURL.hostHandler
         elsif path == '/mail'                               # inbox redirect
          [301, {'Location' => '/d/*/msg*?sort=date&view=table'}, []]
        else
          nodeResponse                                      # local node
        end
      else
        hostHandler
      end
    end

    def hostHandler
      if handler = HostGET[host]                            # host handler
        handler[self]
      elsif host.match?(StoragePool) && %w(jpg png mp4 webm).member?(ext.downcase)
        fetch
      elsif gunk?                                           # gunk handler
        gunkQuery? ? [301, {'Location' => path}, []] : deny
      else                                                  # fetch remote node
        fetch
      end
    end

    alias_method :get, :fetch

    def gunk?
      return false if (query_values||{})['allow'] == ServerKey
      return true if gunkDomain?
      return true if uri.match? Gunk
      false
    end

    def gunkDomain?
      return false if !host || AllowedHosts.has_key?(host) || HostGET.has_key?(host)
      c = GunkHosts                                                 # start cursor
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf in gunk tree
    end

    def gunkQuery?
      !(query_values||{}).keys.grep(/^utm/).empty?
    end

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
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHop.member?(key.downcase)} # output value

      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless (head['Accept']||'').match?(/text\/turtle/) || upstreamUI? # add Turtle to accepted content-types

      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
        head.delete 'Referer'
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
      print_header head if ENV.has_key? 'VERBOSE'
      r = HTTParty.post uri, headers: head, body: body
      head = headers r.headers
      print_header head if ENV.has_key? 'VERBOSE'
      [r.code, head, [r.body]]
    end

    def print_body head, body
      type = head['Content-Type'] || head['content-type']
      puts type
      puts case type
           when 'application/json'
             json = ::JSON.parse body rescue {}
             ::JSON.pretty_generate json
           when /^text\/plain/
             json = ::JSON.parse body rescue nil
             json ? ::JSON.pretty_generate(json) : body
           else
             body
           end
    end

    def print_header header
      print "\n🔗 " + uri
      header.map{|k, v|
        print "\n", [k, v.to_s].join("\t"), ' '}
      print "\n", '_' * 80, ' '
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
      ['https://' , path[7..-1], (query ? ['?',query] : nil) ].join.R env
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

    def upstreamUI; env[:UX] = true; self end

    def upstreamUI?
      env.has_key?(:UX) || ENV.has_key?('UX') ||         # (request or process) environment preference
      parts.member?('embed') ||                          # embed URL
      UIhosts.member?(host) ||                           # host preference
      (env['HTTP_USER_AGENT']||'').match?(/Epiphany/) || # user-agent preference
      (query_values||{})['UI'] == 'upstream'             # query-arg preference
    end
  end
  include HTTP
end
