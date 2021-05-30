# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri pry rack).map{|_| require _}

class WebResource
  module HTTP
    include URIs

    HostGET = {}
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Args = %w(find fullContent notransform offline order sort view)

    def allow_domain?
      c = AllowDomains                                              # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

    def cacheResponse
      timeMeta            # reference temporally-adjacent nodes
      nodes = nodeSet     # find local nodes
      if nodes.size == 1  # one static node. determine if it suits content-negotiated preferences
        static = nodes[0]
        return static.fileResponse if env[:notransform]                  # no transformations per request
        suffix = File.extname static.path                                # format-suffix
        format = MIME_Types[suffix] || Rack::Mime::MIME_TYPES[suffix]    # format
        return static.fileResponse if format&.match? FixedFormat         # no transformations available
        return static.fileResponse if format == (selectFormat format)    # data already in preferred format
      end
      nodes.map &:loadRDF # load graph-data for merging and/or transcoding
      graphResponse       # response
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']    # allow HTTP methods
      uri = RDF::URI('//' + env['HTTP_HOST']).                           # host
              join(env['REQUEST_PATH']).R env                            # path

      uri.scheme = uri.local_node? ? 'http' : 'https'                    # scheme

      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?              # non-empty query
        uri.query = env['QUERY_STRING'].sub(/^&+/,'').sub(/&+$/,'').gsub(/&&+/,'&') # query stripped of excess & chars
        env[:qs] = uri.query_values; qs = uri.query_values               # parse client args
        Args.map{|k|env[k.to_sym] = qs.delete(k)||true if qs.has_key? k} # set local (client <> proxy) args
        qs.empty? ? (uri.query = nil) : (uri.query_values = qs)          # set external (proxy <> origin) query string
      else
        env[:qs] = {}                                                    # no query-args
      end

      env[:client_cache] = env.has_key?('HTTP_IF_NONE_MATCH') || env.has_key?('HTTP_IF_MODIFIED_SINCE') # client-cache existence flag. origin 304 validation becomes 200 for fill from local cache when unset
      env.update({base: uri, feeds: [], links: {}, resp: {}})            # rsponse-environment storage
     #Pry::ColorPrinter.pp env if Verbose                                # log request

      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body|    # dispatch request
        format = uri.format_icon head['Content-Type']                    # log response
        color = if env[:deny]
                  '38;5;196'
                elsif env[:filtered]
                  '38;5;122'
                else
                  format_color format
                end
        puts [env[:deny] ? '🛑' : (action_icon env['REQUEST_METHOD'], env[:fetched]), (status_icon status), format, env[:repository] ? (env[:repository].size.to_s + '⋮') : nil,
              env['HTTP_REFERER'] ? ["\e[#{color}m", env['HTTP_REFERER'], "\e[0m→"] : nil, "\e[#{color}#{env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m",
              env[:base], "\e[0m", head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil, Verbose ? [env['HTTP_ACCEPT'], head['Content-Type']].compact.join(' → ') : nil,
             ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '
        [status, head, body]}                                            # response
    rescue Exception => e                                                # error handler
      puts uri, e.class, e.message, e.backtrace
      [500, {'Content-Type' => 'text/html; charset=utf-8'}, env['REQUEST_METHOD'] == 'HEAD' ? [] : ["<html><body class='error'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri.uri_toolbar]}500</body></html>"]]
    end

    def client_etags
      if tags = env['HTTP_IF_NONE_MATCH']
        tags.strip.split /\s*,\s*/
      else
        []
      end
    end

    def HTTP.decompress head, body
      encoding = head.delete 'Content-Encoding'
      return body unless encoding
      case encoding.to_s
      when /^br(otli)?$/i
        Brotli.inflate body
      when /gzip/i
        (Zlib::GzipReader.new StringIO.new body).read
      when /flate|zip/i
        Zlib::Inflate.inflate body
      else
        puts "undefined Content-Encoding: #{encoding}"
        head['Content-Encoding'] = encoding
        body
      end
    rescue Exception => e
      puts [e.class, e.message].join " "
      head['Content-Encoding'] = encoding
      body
    end
 
    def deny status = 200, type = nil
      env[:deny] = true
      ext = File.extname basename if path
      type, content = if type == :stylesheet || ext == '.css'
                        ['text/css', '']
                      elsif type == :font || %w(.eot .otf .ttf .woff .woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(.bmp .gif .png).member?(ext)
                        ['image/png', SiteIcon]
                      elsif type == :script || ext == '.js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif type == :JSON || ext == '.json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8',
                         "<html><body class='blocked'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri_toolbar]}<a class='unblock' href='#{href}'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       [content]]
    end

    def deny?
      return true  if uri.match? Gunk                   # URI-pattern filter
      return true  if %w(viber whatsapp).member? scheme # scheme filter
      return false if !host || allow_domain? || ScriptHosts.member?(host) # explicit allow
      return true  if deny_domain?                      # DNS filter
             false
    end

    def deny_domain?
      c = DenyDomains                                               # init cursor
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf in domain tree
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env ||= {}
      end
    end

    # fetch data from cache or remote
    def fetch
      return cacheResponse if offline?                                # offline, respond from cache
      ns = nodeSet
      return [304,{},[]] if env[:client_cache] && static_node?        # client has node cached
      return ns[0].fileResponse if ns.size == 1 && ns[0].static_node? # server has node cached, return it
      if timestamp = ns.map{|n|n.node.mtime if n.node.exist?}.compact.sort[0] # cached-version timestamp
        env['HTTP_IF_MODIFIED_SINCE'] = timestamp.httpdate
      end
      case scheme
      when nil
        ['https:', uri].join.R(env).fetchHTTP                         # HTTPS fetch (default scheme)
      when 'gemini'
        fetchGemini                                                   # Gemini fetch
      when /^http/
        fetchHTTP                                                     # HTTPS fetch
      else
        puts "⚠️ unsupported scheme: #{uri}"
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError => e
      puts [e.class, e.message].join ' '
     #if e.class == SocketError && e.message.index('name not known')  # DNS lookup failure
     #  [302,{'Location' => 'http://localhost/https://www.google.com/search' + HTTP.qs({'q' => host})},[]]
      if scheme == 'https'                                            # HTTP fetch on HTTPS failure
        puts "⚠️  fallback scheme #{uri} -> HTTP"
        uri.sub('s','').R(env).fetchHTTP rescue (env[:status] = 408; notfound)
      else
        env[:status] = 408; notfound
      end
    end

    # fetch remote data to in-RAM graph and static file-cache
    def fetchHTTP format: nil, thru: true                             # options: format (override broken remote), craft HTTP response for caller
      URI.open(uri, headers.merge({redirect: false})) do |response|   # fetch over HTTP from remote
        env[:fetched] = true                                          # mark as fetched for logger
        h = headers response.meta                                     # response headers
        case response.status[0].to_i                                  # response status
        when 204                                                      # no content
          [204, {}, []]
        when 206                                                      # partial content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]
        else                                                          # full content
          body = HTTP.decompress h, response.read                     # decompress content
          format ||= if path == '/feed'                               # format fixed on remote feed to ignore erroneous text/html headers
                       'application/atom+xml'
                     elsif content_type = h['Content-Type']           # format defined in HTTP header
                       ct = content_type.split(/;/)
                       if ct.size == 2 && ct[1].index('charset')      # charset defined in HTTP header
                         charset = ct[1].sub(/.*charset=/i,'')
                         charset = nil if charset.empty? || charset == 'empty'
                       end
                       ct[0]
                     end
          if format                                                   # format defined
            if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
              charset = metatag[1]                                    # charset defined in <head>
            end
            if charset
              charset = 'UTF-8' if charset.match? /utf.?8/i           # normalize UTF-8 charset symbol
              charset = 'Shift_JIS' if charset.match? /s(hift)?.?jis/i# normalize Shift-JIS charset symbol
            end                                                       # transcode to UTF-8
            body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/
            if format == 'application/xml' && body[0..2048].match?(/(<|DOCTYPE )html/i)
              format = 'text/html'                                    # HTML in XML clothing
            end
            body = Webize.clean self, body, format                    # clean upstream data
            if formatExt = Suffixes[format] || Suffixes_Rack[format]  # find format-suffix
              file = fsPath                                           # cache path
              file += '/index' if file[-1] == '/'                     # append dir-index slug
              file += formatExt unless File.extname(file)==formatExt  # append format-suffix
              FileUtils.mkdir_p File.dirname file                     # create container
              File.open(file, 'w'){|f| f << body }                    # update data-cache
            else
              puts "⚠️ extension undefined for #{format}"              # ⚠️ undefined format-suffix
            end
            if reader = RDF::Reader.for(content_type: format)         # reader defined for format?
              env[:repository] ||= RDF::Repository.new                # initialize RDF repository
              if timestamp = h['Last-Modified']                       # HTTP timestamp
                if ts = Time.httpdate(timestamp.gsub('-',' ').sub(/((ne|r)?s|ur)?day/,'')) rescue nil
                  FileUtils.touch file, mtime: ts                     # cache mtime
                  env[:repository] << RDF::Statement.new(self, Date.R, ts.iso8601) if format.index 'text' # timestamp RDF
                else
                  puts "⚠️ bad timestamp #{timestamp}"
                end
              end
              reader.new(body, base_uri: self, path: file){|g|env[:repository] << g} # read RDF
            else
              puts "⚠️ Reader undefined for #{format}"                 # ⚠️ undefined Reader
            end unless format.match? /octet-stream/                   # can't parse binary blobs
          else
            puts "⚠️ format undefined on #{uri}"                       # ⚠️ undefined format
          end
          return unless thru                                          # no HTTP response, done fetching to RAM
          saveRDF                                                     # commit graph-cache
          env[:resp]['Access-Control-Allow-Origin'] ||= origin        # CORS header
          h['Link'] && h['Link'].split(',').map{|link|                # Link headers
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}                                                      # upstream headers
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type Last-Modified).map{|k|
            env[:resp][k] ||= h[k] if h[k]}
          env[:resp]['ETag'] ||= h['Etag']                            # ETag header
          if env[:notransform]|| !format ||format.match?(FixedFormat) # no transform
            body = Webize::HTML.resolve_hrefs body, env, true if format == 'text/html' && env.has_key?(:proxy_href) # resolve hrefs in proxy scenario
            env[:resp]['Content-Length'] = body.bytesize.to_s         # Content-Length header
            [200, env[:resp], [body]]                                 # response in upstream format
          else                                                        # content-negotiated transform
            graphResponse format                                      # response in requested format
          end
        end
      end
    rescue Exception => e
      status = e.respond_to?(:io) ? e.io.status[0] : ''
      case status
      when /30[12378]/ # redirected
        dest = (join e.io.meta['location']).R env
        if scheme == 'https' && dest.scheme == 'http'
          puts "⚠️ HTTPS downgraded to HTTP: #{uri} -> #{dest}"
          dest.fetchHTTP
        else
          [302, {'Location' => dest.href}, []]
        end
      when /304/ # upstream Not Modified
        env[:client_cache] ? [304, {}, []] : cacheResponse
      when /300|[45]\d\d/ # Not Found, Not Allowed and misc upstream errors
        env[:status] = status.to_i
        head = headers e.io.meta
        body = HTTP.decompress(head, e.io.read).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        if head['Content-Type']&.index 'html'
          body = Webize::HTML.clean body, self
          env[:repository] ||= RDF::Repository.new
          RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|env[:repository] << g} # read RDF
        end
        head['Content-Length'] = body.bytesize.to_s
        env[:notransform] ? [env[:status], head, [body]] : env[:base].cacheResponse
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      return [304,{},[]] if client_etags.include? env[:resp]['ETag']    # client has file
      Rack::Files.new('.').serving(Rack::Request.new(env), fsPath).yield_self{|s,h,b|
        if 304 == s
          [304, {}, []]                                                 # unmodified file
        else
          if h['Content-Type'] == 'application/javascript'
            h['Content-Type'] = 'application/javascript; charset=utf-8' # add charset 
          elsif !h.has_key?('Content-Type')                             # format missing?
            if mime = Rack::Mime::MIME_TYPES[File.extname path]         # format via Rack extension-map
              h['Content-Type'] = mime
            elsif RDF::Format.file_extensions.has_key? ext.to_sym       # format via RDF extension-map
              h['Content-Type'] = RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
            end
          end
          env[:resp]['Access-Control-Allow-Origin'] ||= origin
          env[:resp]['Content-Length'] = node.size.to_s
          [s, h.update(env[:resp]), b]                                  # file response
        end}
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local_node?
        env[:proxy_href] = true  # enable proxy URIs
        p = parts[0]             # initial path selector
        if !p                    # local root-node
          '/index'.R(env).cacheResponse
        elsif p[-1] == ':'       # remote node - proxy URI
          unproxy.hostHandler
        elsif p == 'favicon.ico' # local icon
          [200, {'Content-Type' => 'image/png'}, [SiteIcon]]
        elsif p.index '.'        # remote node - proxy URI, undefined scheme
          unproxy(true).hostHandler
        elsif %w{m d h}.member? p
          dateDir                # month/day/hour redirect
        elsif p == 'mailto' && parts.size == 2
          [302, {'Location' => ['/m/*/*/*', (parts[1].split(/[\W_]/) - BasicSlugs).map(&:downcase).join('.'), '*?view=table&sort=date'].join}, []]
        else
          cacheResponse          # local node
        end
      else
        hostHandler              # remote node
      end
    end

    def graphResponse defaultFormat='text/html'
      return notfound if !env.has_key?(:repository)||env[:repository].empty? # empty graph
      return [304,{},[]] if client_etags.include? env[:resp]['ETag']         # client has file
      status = env[:status] || 200                                           # response status
      format = selectFormat defaultFormat                                    # response format
      env[:resp]['Access-Control-Allow-Origin'] ||= origin                   # response headers
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      return [status, env[:resp], nil] if env['REQUEST_METHOD'] == 'HEAD'    # header-only response

      body = case format                                                     # response body
             when /html/
               htmlDocument                                                  # serialize HTML
             when /atom|rss|xml/
               feedDocument                                                  # serialize Atom/RSS
             else                                                            # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 puts "no Writer for #{format}"
                 ''
               end
             end
      env[:resp]['Content-Length'] = body.bytesize.to_s                      # response size

      [status, env[:resp], [body]]                                           # graph response
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # return status and header
    end

    # client<>proxy connection-specific headers not reused on proxy<>origin connection
    SingleHopHeaders = %w(connection host keep-alive path-info query-string
 remote-addr request-method request-path request-uri script-name server-name server-port server-protocol server-software
 te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for)

    def headers raw = nil
      raw ||= env || {}                                     # raw headers
      head = {}                                             # cleaned headers
      raw.map{|k,v|                                         # inspect (k,v) pairs
        unless k.class != String || k.index('rack.') == 0   # strip Rack-internal headers
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip Rack prefix and tokenize
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t # acronyms
              t = t.upcase                                  # upcase acronym
            else
              t[0] = t[0].upcase                            # capitalize
            end
            t}.join '-'                                     # join tokens
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase # set header
        end}

      head['Referer'] = 'http://drudgereport.com/' if host.match? /wsj\.com$/
      head['Referer'] = 'https://' + host + '/' if (path && %w(.gif .jpeg .jpg .png .svg .webp).member?(File.extname(path).downcase)) || parts.member?('embed')
      head['User-Agent'] = if %w(po.st t.co).member? host   # prefer shortlink-expansion in HTTP-headers over procedural Javascript, advertise a basic user-agent
                             'curl/7.65.1'
                           else
                             'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36'
                           end
      head
    end

    def hostHandler
      URIs.denylist                                         # refresh denylist
      qs = query_values || {}                               # parse query
      cookie = join('/cookie').R                            # cookie-jar URI
      cookie.writeFile qs['cookie'] if qs['cookie'] && !qs['cookie'].empty? # store cookie to jar
      env['HTTP_COOKIE'] = cookie.readFile if cookie.node.exist? # read cookie from jar
      if path == '/favicon.ico'                             # icon handler
        node.exist? ? fileResponse : fetch
      elsif qs['download'] == 'audio'                       # download from remote
        slug = qs['list'] || qs['v'] || 'audio'
        storageURI = join([basename, slug].join '.').R
        storage = storageURI.fsPath
        unless File.directory? storage
          FileUtils.mkdir_p storage
          pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{uri}\""
          Process.detach pid
        end
        [302, {'Location' => storageURI.href + '?offline'}, []]
      elsif parts[-1]&.match? /^(gen(erate)?|log)_?204$/    # 204 response, skip roundtrip to origin
        [204, {}, []]
      elsif query&.match? Gunk                              # query-gunk
        [301,{'Location' => ['//',host,path].join.R(env).href},[]] # redirect to queryless
      elsif handler = HostGET[host]                         # custom handler: lambda
        handler[self]
      elsif deny?                                           # block request
        deny
      else                                                  # generic handler: remote node cache
        fetch
      end
    end

    def notfound
      [env[:status] || 404, {'Content-Type' => 'text/html'}, [htmlDocument({'#req'=>env})]]
    end

    def offline?
      ENV.has_key?('OFFLINE') || env.has_key?(:offline)
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

    def OPTIONS
      if allow_domain? && !uri.match?(Gunk)                 # POST allowed?
        head = headers                                      # read head
        body = env['rack.input'].read                       # read body
        env.delete 'rack.input'

        if Verbose                                          # log request
          puts 'OPTIONS ' + uri
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '>>>>>>>>', body
        end

        r = HTTParty.options uri, headers: head, body: body # OPTIONS request to origin
        head = headers r.headers                            # response headers
        body = r.body

        if Verbose                                          # log response
          puts '-' * 40
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '<<<<<<<<', body unless head['Content-Encoding']
        end

        [r.code, head, [body]]                              # response
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => AllowedHeaders,
               'Access-Control-Allow-Origin' => origin}, []]
      end
    end

    def POST
      if allow_domain? && !uri.match?(Gunk)                 # POST allowed?
        head = headers                                      # read head
        body = env['rack.input'].read                       # read body
        env.delete 'rack.input'

        if Verbose                                          # log request
          puts 'POST ' + uri
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '>>>>>>>>', body
        end

        r = HTTParty.post uri, headers: head, body: body    # POST to origin
        head = headers r.headers                            # response headers
        body = r.body

        if format = head['Content-Type']                    # response format
          if reader = RDF::Reader.for(content_type: format) # reader defined for format?
            env[:repository] ||= RDF::Repository.new        # initialize RDF repository
            reader.new(HTTP.decompress({'Content-Encoding' => head['Content-Encoding']}, body), base_uri: self){|g|
              env[:repository] << g}                        # read RDF
            saveRDF                                         # cache RDF
          else
            puts "RDF::Reader undefined for #{format}"      # Reader undefined
          end
        end

        if Verbose                                          # log response
          puts '-' * 40
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '<<<<<<<<', body unless head['Content-Encoding']
        end

        [r.code, head, [body]]                              # response
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Origin' => origin}, []]
      end
    end

    def selectFormat default = nil                          # default-format argument
      default ||= 'text/html'                               # default when unspecified
      return default unless env.has_key? 'HTTP_ACCEPT'      # no preference specified
      category = default.split('/')[0]+'/*'                 # format-category wildcard symbol
      all = '*/*'                                           # any-format wildcard symbol

      index = {}                                            # build (q-value -> format) index
      env['HTTP_ACCEPT'].split(/,/).map{|e|                 # header values
        fmt, q = e.split /;/                                # (MIME, q-value) pair
        i = q && q.split(/=/)[1].to_f || 1                  # default q-value
        index[i] ||= []                                     # q-value entry
        index[i].push fmt.strip}                            # insert format at q-value

      index.sort.reverse.map{|_, accepted|                  # search in descending q-value order
        return default if accepted.member? all              # anything accepted here
        return default if accepted.member? category         # category accepted here
        accepted.map{|format|
          return format if RDF::Writer.for(:content_type => format) || # RDF writer available for format
             ['application/atom+xml','text/html'].member?(format)}}    # non-RDF writer available
      default                                                          # search failure
    end

    def unproxy schemeless = false
      env[:base] = [schemeless ? ['/', path] : path[1..-1], query ? ['?', query] : nil].join.R(env)
    end

  end
  include HTTP
end
