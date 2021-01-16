# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}

class WebResource
  module HTTP
    include URIs

    HostGET = {}

    def allow_domain?
      c = AllowDomains                                              # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

    def cacheResponse
      nodes = nodeSet            # find nodes
      if nodes.size == 1 && (nodes[0].static_node? || # one node of preferred or fixed format
                            (nodes[0].named_format == selectFormat && (no_transform? || nodes[0].named_format != 'text/html')))
        nodes[0].fileResponse    # static response
      else
        nodes.map{|n|            # load graph-data
          env[:summary] ? n.summary : n.🐢}.map &:loadRDF
        saveRDF if env[:updates] # cache resources discovered in RDFization
        graphResponse            # graph response
      end
    end

    def self.call env
      return [405,{},[]] unless %w(GET HEAD OPTIONS POST PUT).member? env['REQUEST_METHOD'] # allow methods
      uri = RDF::URI('//' + env['HTTP_HOST']).join(env['REQUEST_PATH']).R env # request URI
      uri.scheme = uri.local_node? ? 'http' : 'https'                         # URI scheme
      uri.query = env['QUERY_STRING'].sub(/^&/,'').gsub(/&&+/,'&') if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # strip leading + consecutive & from qs so URI library doesn't freak out
      env.update({base: uri, feeds: [], links: {}, resp: {}})                 # request environment
      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body| # dispatch request
        format = uri.format_icon head['Content-Type']                 # logger
        color = env[:deny] ? '31;1' : (format_color format)
        puts [env[:deny] ? '🛑' : (action_icon env['REQUEST_METHOD'], env[:fetched]), (status_icon status), format,
              env[:repository] ? (env[:repository].size.to_s + '⋮') : nil,
              env['HTTP_REFERER'] ? ["\e[#{color}m", env['HTTP_REFERER'], "\e[0m→"] : nil,
              "\e[#{color}#{env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m",
              env[:base], "\e[0m", head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil,
              [env['HTTP_ACCEPT'], head['Content-Type']].compact.join(' → ')
             ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '
        [status, head, body]} # response
    rescue Exception => e
      msg = [[uri, e.class, e.message].join(' '), e.backtrace].join "\n"
      puts "\e[7;31m500\e[0m " + msg
      [500, {'Content-Type' => 'text/html; charset=utf-8'}, env['REQUEST_METHOD'] == 'HEAD' ? [] : ["<!DOCTYPE html>\n<html><body class='error'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri.uri_toolbar]}<pre><a href='#{uri.remoteURL}' >500</a>\n#{CGI.escapeHTML msg}</pre></body></html>"]]
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
 
    def deny status = 200, type = nil
      return [302, {'Location' => ['//', host, path].join.R(env).href}, []] if query&.match? Gunk # strip query
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
                         "<html><body class='blocked'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri_toolbar]}<a class='unblock' href='#{uri}'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       [content]]
    end

    def deny?
      return true  if uri.match? Gunk # URI filter
      return false if !host || HostGET.has_key?(host)
      return false if allow_domain?   # DNS filters
      return true  if deny_domain?
             false
    end

    def deny_domain?
      c = DenyDomains                                               # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

    # if needed, generate and return entity. delegated to Rack handler if file reference
    def entity generator = nil
      if env['HTTP_IF_NONE_MATCH']&.strip&.split(/\s*,\s*/)&.include? env[:resp]['ETag']
        [304, {}, []]                            # unmodified entity
      else
        body = generator ? generator.call : self # generate entity
        if body.class == WebResource             # entity is a resource-reference
          Rack::Files.new('.').serving(Rack::Request.new(env), body.fsPath).yield_self{|s,h,b|
            if 304 == s
              [304, {}, []]                      # unmodified file
            else
              if h['Content-Type'] == 'application/javascript'
                h['Content-Type'] = 'application/javascript; charset=utf-8' # add charset tag
              elsif !h.has_key?('Content-Type')                            # format-hint missing?
                if mime = Rack::Mime::MIME_TYPES[body.extension]           # format via Rack extension-map
                  h['Content-Type'] = mime
                elsif RDF::Format.file_extensions.has_key? body.ext.to_sym # format via RDF extension-map
                  h['Content-Type'] = RDF::Format.file_extensions[body.ext.to_sym][0].content_type[0]
                end
              end
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]       # return file
            end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [200, env[:resp], [body]]              # return data
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

    # fetch from cache or remote
    def fetch
      return cacheResponse if offline?
      return [304,{},[]] if (env.has_key?('HTTP_IF_NONE_MATCH') || env.has_key?('HTTP_IF_MODIFIED_SINCE')) && static_node? # client has static node cached
      nodes = nodeSet; return nodes[0].fileResponse if nodes.size == 1 && nodes[0].static_node?                            # server has static node cached
      fetchHTTP                                                                 # fetch via HTTPS
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      ['http://', host, ![nil, 443].member?(port) ? [':', port] : nil, path, query ? ['?', query] : nil].join.R(env).fetchHTTP # fetch via HTTP
    end

    # fetch from remote, read graph-data, fill graph+static caches, maybe return HTTP response
    def fetchHTTP thru: true, transformable: !no_transform? # allow format conversion and rewrite (HTML reformat, code pretty-print)
      url = transformable ? uri : (uri.sub /\?notransform$/, '') # strip local query-arg
      URI.open(url, headers.merge({redirect: false})) do |response| ; env[:fetched] = true
        h = response.meta                                             # response headerd
        if response.status.to_s.match? /206/                          # partial response
          h['Access-Control-Allow-Origin'] = origin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                                   # respond with part
        else
          body = HTTP.decompress h, response.read                     # response body

          format = if path=='/feed'||(query_values||{})['mime']=='xml'# feed URL (override HTTP-metadata content-type)
                     'application/atom+xml'
                   elsif content_type = h['content-type']             # format defined in HTTP metadata
                     ct = content_type.split(/;/)
                     if ct.size == 2
                       charset = ct[1].sub(/.*charset=/i,'')
                       unless charset.match? /utf.*8/i
                         puts "transcoding #{charset} doc to UTF-8"
                         charset = nil if charset.empty? || charset=='empty'
                         body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace
                       end
                     end
                     ct[0]
                   elsif named_format                                 # format from name extension mapping
                     named_format
                   end

          if format                                                   # format defined?
            body = Webize::CSS.clean body if format.index('text/css') == 0 # clean upstream document
            body = Webize::HTML.clean body, self if format.index('text/html') ==0
            body = Webize::Code.clean body, self if format.index('script')
            if formatExt = Suffixes[format] || Suffixes_Rack[format]  # look up format-suffix
              if extension == formatExt                               # suffix agrees w/ reverse map
                cache = self                                          # cache at canonical location
              else                                                    # format-suffix mismatch
                cache = uri
                cache += 'index' if uri[-1] == '/'                    # append directory-data slug
                cache += formatExt                                    # append suffix
                cache = cache.R
              end
              cache.writeFile body if cache.static_node?              # cache static data
            else
              puts "extension undefined for #{format}"                # warn: undefined format-suffix
            end
            if reader = RDF::Reader.for(content_type: format)         # reader defined for format?
              env[:repository] ||= RDF::Repository.new                # initialize RDF repository
              if timestamp = h['Last-Modified'] || h['last-modified'] # HTTP metadata to RDF-graph
                env[:repository] << RDF::Statement.new(self, Date.R, Time.httpdate(timestamp.gsub('-',' ').sub(/((ne|r)?s|ur)?day/,'')).iso8601) rescue nil
              end
              reader.new(body, base_uri: self){|g|env[:repository] << g} # read RDF
            else
              puts "RDF::Reader undefined for #{format}" unless %w(css js).member? ext # warn: undefined Reader
            end
          else
            puts "ERROR format undefined on #{uri}"                   # warn: undefined format
          end

          return unless thru                                          # skip HTTP response

          saveRDF                                                     # cache graph-data

          env[:resp]['Access-Control-Allow-Origin'] ||= origin        # CORS header
          h['link'] && h['link'].split(',').map{|link|                # Link headers
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}         # misc upstream headers

          if transformable && !(format||'').match?(/audio|css|image|octet|script|video/) # can transcode/reformat
            graphResponse                                             # doc in local reformat
          else
            env[:resp]['Content-Length'] = body.bytesize.to_s         # Content-Length header
            [200, env[:resp], [body]]                                 # doc in original format
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
      when /300|[45]\d\d/ # Not Found, Not Allowed or general upstream error
        env[:origin_status] = status.to_i
        if transformable
          if e.io.meta['content-type']&.match? /text\/html/
            (env[:repository] ||= RDF::Repository.new) << RDF::Statement.new(self, Content.R,
                                                                             Webize::HTML.format(HTTP.decompress(e.io.meta, e.io.read), self)) # upstream message
          end
          env[:base].cacheResponse
        else
          [env[:origin_status], (headers e.io.meta), [e.io.read]]
        end
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= origin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local_node?
        p = parts[0]
        if !p
          [302, {'Location' => '/h'}, []]
        elsif %w{m d h}.member? p              # goto current day/hour/min dir
          dateDir
        elsif path == '/favicon.ico'
          [200, {'Content-Type' => 'image/png'}, [SiteIcon]]
        elsif path == '/log' || path == '/log/'
          log_search                           # search log
        elsif path == '/mail'                  # goto inbox
          [302, {'Location' => '/d?f=msg*'}, []]
        elsif !p.match? /[.:]/                 # no hostname/scheme characters
          timeMeta                             # reference temporally-adjacent nodes
          cacheResponse                        # local node
        else
          (env[:base] = remoteURL).hostHandler # host handler (rebased on localhost)
        end
      else
        hostHandler                            # host handler
      end
    end

    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
      format = selectFormat
      env[:resp]['Access-Control-Allow-Origin'] ||= origin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument
        when /^application\/atom+xml/
          feedDocument
        else
          env[:repository].dump RDF::Writer.for(content_type: format).to_sym, base_uri: self
        end}
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # status and header
    end

    # headers cleaned/filtered for export
    def headers raw = nil
      raw ||= env || {} # raw headers
      head = {}         # clean headers
      raw.map{|k,v|     # inspect headers
        k = k.to_s
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix, tokenize
          if %w{cl dfe dnt id spf utc xsrf}.member? t # acronyms
            t = t.upcase                          # upcase
          else
            t[0] = t[0].upcase                    # capitalize
          end
          t                                       # token
        }.join(k.match?(/(_AP_|PASS_SFP)/i) ? '_' : '-') # join tokens
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless %w(base colors connection downloadable feeds fetched graph host images keep-alive links origin-status path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rack.tempfiles remote-addr repository request-method request-path request-uri resp script-name searchable server-name server-port server-protocol server-software summary sort te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for).member?(key.downcase)} # external multi-hop headers

      head['Accept'] = ['text/turtle', head['Accept']].join ',' unless (head['Accept']||'').match?(/text\/turtle/) # we accept Turtle even if requesting client doesnt
      head['Referer'] = 'http://drudgereport.com/' if host.match? /wsj\.com$/
      head['Referer'] = 'https://' + host + '/' if %w(gif jpeg jpg png svg webp).member?(ext.downcase) || parts.member?('embed')
      head['User-Agent'] = if %w(po.st t.co).member? host # we want shortlink-expansion via HTTP-redirect, not Javascript, so advertise a basic user-agent
                             'curl/7.65.1'
                           else
                             'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36'
                           end
      head
    end

    def hostHandler
      qs = query_values || {}
      cookie = join('/cookie').R
      cookie.writeFile qs['cookie'] if qs['cookie'] && !qs['cookie'].empty? # cache cookie
      env['HTTP_COOKIE'] = cookie.readFile if cookie.node.exist? # fetch cookie from jar
      if last = parts[-1]
        case last
        when /^gen(erate)?_?204$/
          return [204, {}, []]
        when /^new|message|rss/i
          env[:sort] ||= 'date'
          env[:view] ||= 'table'
        end
      end
      if path == '/favicon.ico' && node.exist?
        fileResponse
      elsif qs['download'] == 'audio'
        slug = qs['list'] || qs['v'] || 'audio'
        storageURI = join([basename, slug].join '.').R
        storage = storageURI.fsPath
        unless File.directory? storage
          FileUtils.mkdir_p storage
          pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{uri}\""
          Process.detach pid
        end
        [302, {'Location' => storageURI.href + '?offline'}, []]
      elsif handler = HostGET[host] # host lambda
        handler[self]
      elsif deny?
        deny
      else                       # remote graph-node
        fetch
      end
    end

    def log_search
      env.update({sort: sizeAttr = '#size', view: 'table'})
      results = {}
      if q = (query_values||{})['q']
        `grep --text -i #{Shellwords.escape 'http.*' + q} web.log | tr -s ' ' | cut -d ' ' -f 7 `.each_line{|uri|
          u = uri.R
          results[uri] ||=  {'uri' => uri,
                             sizeAttr => 0,
                             Title => [[u.host, u.path, (u.query ? ['?', u.query] : nil)].join]}
          results[uri][sizeAttr] += 1}
      end
      [200, {'Content-Type' => 'text/html'}, [(htmlDocument results)]]
    end

    def no_transform?; (query_values||{}).has_key? 'notransform' end

    def notfound; [env[:origin_status] || 404,
                   {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def offline?
      ENV.has_key?('OFFLINE') || (query_values||{}).has_key?('offline')
    end

    def origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' if !h || h.empty?
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def POST
      if allow_domain?                                  # POST allowed?
        head = headers                                  # read headers
        body = env['rack.input'].read                   # read body
        env.delete 'rack.input'
        if Verbose
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '>>>>>>>>', body, '--------'
        end

        r = HTTParty.post uri, headers: head, body: body # POST to origin

        head = headers r.headers                            # response headers
        if format  = head['Content-Type']                   # response format
          if reader = RDF::Reader.for(content_type: format) # reader defined for format?
            env[:repository] ||= RDF::Repository.new        # initialize RDF repository
            reader.new(HTTP.decompress(head, r.body), base_uri: self){|g|env[:repository] << g} # read RDF
            saveRDF                                         # cache RDF
          else
            puts "RDF::Reader undefined for #{format}"      # Reader undefined
          end
        end

        if Verbose
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '<<<<<<<<', HTTP.decompress(head, r.body)
        end

        [r.code, head, [r.body]]
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Origin' => origin}, []]
      end
    end

    def remoteURL
      ['https:/' , path.sub(/^\/https?:\//,''),
       (query ? ['?', query] : nil),
       (fragment ? ['#', fragment] : nil) ].join.R env
    end

  end
  include HTTP
end
