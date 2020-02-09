# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    AllowedHosts = {}
    CookieHosts = {}
    GlobChars = /[\*\{\[]/
    HostGET = {}
    HostPOST = {}
    HTTPHosts = {}
    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq
    LocalArgs = %w(allow view sort UX)
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Populator = {}
    Req204 = /gen(erate)?_?204$/
    Servers = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert
    Internal_Headers = %w(
base-uri connection gunk keep-alive links path-info query-string
rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version
rdf refhost remote-addr repository request-method request-path request-uri resp
script-name server-name server-port server-protocol server-software site-chrome
te transfer-encoding
unicorn.socket upgrade upgrade-insecure-requests ux version x-forwarded-for
)

    # handlers
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.query_values&.has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.query_values['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['q'])}, []]}
    NoGunk  = -> r {r.gunkURI && (r.query_values || {})['allow'] != ServerKey && r.deny || r.fetch}
    NoJS    = -> r {
      if r.ext == 'js'                             # request for script file
        r.deny                                     # drop request
      else
        NoGunk[r].yield_self{|s,h,b|               # inspect response
          format = h['content-type'] || h['Content-Type']
          if s.to_s.match? /^3/                    # redirected
            [s,h,b]
          elsif !format || format.match?(/script/) # response with script source
            r.deny                                 # drop response
          elsif format.match?(/html/) && r.upstreamUI?
            doc = Nokogiri::HTML.parse b[0]        # parse HTML
            doc.css(Webize::HTML::Scripts).remove# drop JS-gunk
            body = doc.to_html                     # serialize body
            h['Content-Length']=body.bytesize.to_s # update body-size
            [s, h, [body]]                         # cleaned response
          else
            [s,h,b]                                # untouched response
          end}
      end}

    NoQuery = -> r {
      if !r.query                         # request without query
        NoGunk[r].yield_self{|s,h,b|      #  inspect response
          h.keys.map{|k|                  #  strip query from new location
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                        #  response
      else                                # request with query
        [302, {'Location' => r.path}, []] #  redirect to path
      end}

    RootIndex = -> r {
      if r.path == '/' || r.path.match?(GlobChars)
        r.nodeResponse
      else
        r.chrono_sort if r.parts.size == 1
        NoGunk[r]
      end}

    R204 = [204, {}, []]
    R304 = [304, {}, []]

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      @cookies || AllowedHosts.has_key?(host) || CookieHosts.has_key?(host) || CookieHost.match?(host)
    end

    def allowCDN?
      if host.match? /github.io$/
        env[:refhost]&.match? /github.io$/
      else
        (CacheExt - %w(html js)).member?(ext.downcase) && !path.match?(Gunk)
      end
    end

    def allowedOrigin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (env['SERVER_NAME'] == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']           # allow HTTP methods
      uri = RDF::URI('https://' + env['SERVER_NAME']).join env['REQUEST_PATH']
      uri.query = env['QUERY_STRING'] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
      resource = uri.R env                                                      # instantiate request
      env[:base_uri] = resource                                                 # request URI
      env[:refhost] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}                                                           # HEAD storage
      env[:links] = {}                                                          # Link storage
      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch

        ext = resource.path ? resource.ext.downcase : ''                        # log
        mime = head['Content-Type'] || ''

        # log host on first visit
        unless (Servers.has_key? env['SERVER_NAME']) || resource.env[:deny]
          Servers[env['SERVER_NAME']] = true
          print "\n      ➕ \e[35;1mhttps://" + env['SERVER_NAME'] + "\e[0m " unless ENV.has_key? 'QUIET'
        end

        if resource.env[:deny]
          if %w(css eot otf ttf woff woff2).member?(ext) || resource.path.match?(/204$/)
            print "🛑"
          else
            print "\n" + (env['REQUEST_METHOD'] == 'POST' ? "\e[31;7;1m📝 " : "🛑 \e[31;1m") + (env[:refhost] ? ("\e[7m" + env[:refhost] + "\e[0m\e[31;1m → ") : '') + (env[:refhost] == resource.host ? '' : ('http://' + resource.host)) + "\e[7m" + resource.path + "\e[0m\e[31m" + "\e[0m "
          end

        # OPTIONS
        elsif env['REQUEST_METHOD'] == 'OPTIONS'
          print "\n🔧 \e[32;1m#{resource.uri}\e[0m "

        # POST
        elsif env['REQUEST_METHOD'] == 'POST'
          print "\n📝 \e[32;1m#{resource.uri}\e[0m "

        # non-content response
        elsif [301, 302, 303].member? status
          print "\n", resource.uri ," ➡️  ", head['Location'] # redirection
        elsif [204, 304].member? status
          print '✅'                    # up-to-date
        elsif status == 404
          print "\n❓ #{resource.uri} " # not found

        # content response
        elsif ext == 'css'                                       # stylesheet
          print '🎨'
        elsif ext == 'js' || mime.match?(/script/)               # script
          third_party = env[:refhost] != resource.host
          print "\n📜 \e[36#{third_party ? ';7' : ''};1mhttps://" + resource.host + resource.path + "\e[0m "
        elsif ext == 'json' || mime.match?(/json/)               # data
          print "\n🗒 " + resource.uri
        elsif %w(gif jpeg jpg png svg webp).member?(ext) || mime.match?(/^image/)
          print '🖼️'                                              # image
        elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
          print '🔉'                                             # audio
        elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
          print '🎬'                                             # video
        elsif ext == 'ttl' || mime == 'text/turtle; charset=utf-8'
          print '🐢'                                             # turtle

        else # default log
          print "\n" + (mime.match?(/html/) ? '📃' : mime) + (env[:repository] ? (('%5d' % env[:repository].size) + '⋮ ') : '') + "\e[7m" + (status == 200 ? '' : (status.to_s+' ')) + resource.uri + "\e[0m "
        end
        
        [status, head, body]} # response
    rescue Exception => e
      uri = 'https://' + env['SERVER_NAME'] + (env['REQUEST_URI']||'')
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

    def dateDir
      time = Time.now
      loc = time.strftime(case parts[0][0].downcase
                          when 'y'
                            '/%Y/'
                          when 'm'
                            '/%Y/%m/'
                          when 'd'
                            '/%Y/%m/%d/'
                          when 'h'
                            '/%Y/%m/%d/%H/'
                          else
                          end)
      [303, env[:resp].update({'Location' => loc + parts[1..-1].join('/') + (env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || '')}), []]
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

    def default_port?
      [80, 443].member? (env['SERVER_PORT'] || 443).to_i
    end

    def deny status=200, type=nil
      env[:deny] = true
      type, content = if type == :stylesheet || ext == 'css'
                        ['text/css', '']
                      elsif type == :font || %w(eot otf ttf woff woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(gif png).member?(ext)
                        ['image/gif', SiteGIF]
                      elsif type == :script || ext == 'js'
                        source = SiteDir.join 'alternatives/' + host + path
                        ['application/javascript', source.exist? ? source.read : '//']
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
      HTTP.print_body headers, env['rack.input'].read if ENV.has_key? 'VERBOSE'
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/
      if entities && entities.include?(env[:resp]['ETag'])
        R304                                     # unmodified resource
      else
        body = generator ? generator.call : self # generate resource
        if body.class == WebResource             # resource reference
          Rack::Files.new('.').serving(Rack::Request.new(env), body.fsPath).yield_self{|s,h,b|
            if 304 == s
              R304                               # unmodified resource
            else                                 # file reference
              h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type'] == 'application/javascript'
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]       # file handler
            end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [200, env[:resp], [body]] # generated entity
        end
      end
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env
      end
    end

    # fetch node from cache or remote server
    def fetch options=nil
      options ||= {}

      # cached results TODO Find static resource when ext changed due to erroneous upstream MIME or extension
      if (CacheExt - %w(json html xml)).member?(ext.downcase) && !host.match?(DynamicImgHost)
        return R304 if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has static-data, return 304 response
        return fileResponse if node.file?                            # server has static-data, return data
      end
      return nodeResponse if ENV.has_key? 'OFFLINE'                  # offline, return cache

      # construct locator
      portNum = default_port? ? '' : (':' + env['SERVER_PORT'].to_s) # port number
      qs = if options[:query]                                        # query string
             HTTP.qs options[:query]
           elsif query
             '?' + query
           else
             ''
           end
      u = ['//', host, portNum, path, options[:suffix], qs].join     # locator sans scheme
      primary  = ('http' + (insecure? ? '' : 's') + ':' + u).R env   # primary-scheme locator
      fallback = ('http' + (insecure? ? 's' : '') + ':' + u).R env   # fallback-scheme locator

      # network fetch
      primary.fetchHTTP options
    rescue Exception => e
      case e.class.to_s
      when 'Errno::ECONNREFUSED'
        fallback.fetchHTTP options
      when 'Errno::ECONNRESET'
        fallback.fetchHTTP options
      when 'Errno::EHOSTUNREACH'
        fallback.fetchHTTP options
      when 'Errno::ENETUNREACH'
        fallback.fetchHTTP options
      when 'Net::OpenTimeout'
        fallback.fetchHTTP options
      when 'Net::ReadTimeout'
        fallback.fetchHTTP options
      when 'OpenSSL::SSL::SSLError'
        fallback.fetchHTTP options
      when 'OpenURI::HTTPError'
        fallback.fetchHTTP options
      when 'RuntimeError'
        fallback.fetchHTTP options
      when 'SocketError'
        fallback.fetchHTTP options
      else
        raise
      end
    end

    def fetchHTTP options = {}
      if ENV.has_key? 'VERBOSE'
        print "\n🐕  #{uri} "
      else
        print '🌍🌎🌏🌐'[rand 4] if options[:intermediate] # give some feedback a fetch occured in intermediate-mode
      end
      # TODO set if-modified-since/etag headers from local cache contents (eattr support sufficient for etag metadata?)
      URI.open(uri, headers.merge({redirect: false})) do |response|
        h = response.meta                                             # upstream metadata
        if response.status.to_s.match? /206/                          # partial response
          h['Access-Control-Allow-Origin'] = allowedOrigin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                                   # return part downstream
        else
          body = HTTP.decompress h, response.read                     # decompress body
          format = if path == '/feed' || (query_values||{})['mime']=='xml'   # content-type
                     'application/atom+xml'
                   elsif h.has_key? 'content-type'
                     h['content-type'].split(/;/)[0]
                   elsif RDF::Format.file_extensions.has_key? ext.to_sym
                     puts "ENOTYPE on #{uri} , pathname determines MIME"
                     RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
                   end
          static = fixedFormat? format                                # rewritable format?
          body = Webize::HTML.degunk body, static if format == 'text/html' && !AllowedHosts.has_key?(host) # clean HTML
          formatExt = Suffixes[format] || Suffixes_Rack[format] || (puts "ENOSUFFIX #{format} #{uri}";'') # filename-extension for format
          storage = fsPath                                            # storage location
          storage += formatExt unless extension == formatExt
          storage.R.writeFile body                                    # cache body
          reader = RDF::Reader.for content_type: format               # select reader
          reader.new(body,base_uri: env[:base_uri],noRDF: options[:noRDF]){|_| # instantiate reader
            (env[:repository] ||= RDF::Repository.new) << _ } if reader # read RDF
          return self if options[:intermediate]                       # intermediate fetch, return w/o HTTP-response
          reader ? saveRDF : (puts "ENORDF #{format} #{uri}")         # cache RDF
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}         # expose upstream metadata to downstream
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin # CORS header
          env[:resp]['Set-Cookie'] = h['set-cookie'] if h['set-cookie'] && allowCookies?
          if static
            env[:resp]['Content-Length'] = body.bytesize.to_s         # size header
            [200, env[:resp], [body]]                                 # upstream doc
          else
            graphResponse                                             # local doc
          end
        end
      end
    rescue Exception => e
      case e.message
      when /300/ # Multiple Choices
        [300, (headers e.io.meta), [e.io.read]]
      when /30[12378]/ # Relocated
        dest = e.io.meta['location'].R env
        same_path = (path || '/') == (dest.path || '/')
        same_host = host == dest.host
        scheme_downgrade = scheme == 'https' && dest.scheme == 'http'
        if same_path && same_host && scheme_downgrade
          puts "WARNING HTTPS downgraded to HTTP at #{uri}"
          dest.fetchHTTP options
        else
          [302, {'Location' => dest.uri}, []]
        end
      when /304/ # Not Modified
        R304
      when /401/ # Unauthorized
        print "\n🚫401 " + uri + ' '
        options[:intermediate] ? self : nodeResponse
      when /403/ # Forbidden
        print "\n🚫403 " + uri + ' '
        options[:intermediate] ? self : nodeResponse
      when /404/ # Not Found
        print "\n❓ #{uri} "
        if options[:intermediate]
          self
        elsif upstreamUI?
          [404, (headers e.io.meta), [e.io.read]]
        else
          nodeResponse
        end
      when /410/ # Gone
        print "\n❌ " + uri + ' '
        options[:intermediate] ? self : nodeResponse
      when /(500|999)/ # upstream error
        [500, (headers e.io.meta), [e.io.read]]
      when /503/
        @cookies = true
        [503, (headers e.io.meta), [e.io.read]]
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def fixedFormat? format = nil
      return true if upstreamUI? || format.to_s.match?(/dash.xml/)
      return false if (query_values||{}).has_key?('rdf') || env[:transform] || !format || format.match?(/atom|html|rss|xml/i)
      return true
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local?                   ## local
        if %w{y year m month d day h hour}.member? parts[0]
          dateDir                   # timeline redirect
        elsif path == '/mail'       # inbox redirect
          [302, {'Location' => '/d/*/msg*?sort=date&view=table'}, []]
        elsif parts[0] == 'msg'     # Message-ID <> URI mapping (TODO move this to #fsPath?)
          id = parts[1]
          id ? MID2PATH[Rack::Utils.unescape_path id].R(env).nodeResponse : notfound
        else                        # local graph-node
          nodeResponse
        end                        ## remote
      elsif path.match? Req204      # connectivity check
        R204
      elsif path.match? HourDir     # browse cache of remote. remove this if remotes get hour-dirs for us
        (path + '*' + host.split('.').-(Webize::Plaintext::BasicSlugs).join('.') + '*').R(env).nodeResponse
      elsif handler = HostGET[host] # host handler
        Populator[host][self] if Populator[host] && !join('/').R.node.exist?
        handler[self]
      elsif host.match? CDNhost     # CDN handler
        (AllowedHosts.has_key?(host) || (query_values||{})['allow'] == ServerKey || allowCDN?) ? fetch : deny
      elsif gunk?                   # blocker handler
        deny
      else
        fetch                       # remote graph-node
      end
    end

    alias_method :get, :fetch

    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
      unless !path || path == '/'
        dir = File.dirname path
        env[:links][:up] = dir + (dir[-1] == '/' ? '' : '/') + (query ? ('?' + query) : '')
      end
      format = selectFormat
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument
        when /^application\/atom+xml/
          feedDocument
        else
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :standard_prefixes => true, :base_uri => env[:base_uri]
        end}
    end

    def gunk?
      return false if (query_values||{})['allow'] == ServerKey
      gunkTag? || gunkURI
    end

    def gunkDomain?
      return false if !host || AllowedHosts.has_key?(host) || HostGET.has_key?(host)
      c = GunkHosts
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf on gunk-domain tree
    end

    def gunkTag?
      return false if AllowedHosts.has_key? host
      env.has_key? 'HTTP_GUNK'
    end

    def gunkURI
      ('/' + host + (env && env['REQUEST_URI'] || path || '/')).match? Gunk
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # return header
    end

    # headers formatted and filtered
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
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless Internal_Headers.member?(key.downcase)} # output value

      # Cookies / Referer / User-Agent
      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
        head.delete 'Referer'
      end
      case env['SERVER_NAME']
      when /wsj\.com$/
        head['Referer'] = 'http://drudgereport.com/' # thanks, Matt
      when /youtube.com$/
        head['Referer'] = 'https://www.youtube.com/' # make 3rd-party embeds work
      end if env['SERVER_NAME']
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st' # we want redirection in HTTP HEAD-Location not Javascript
      head.delete 'User-Agent' if host == 't.co'            # so advertise a 'dumb' user-agent

      HTTP.print_header head if ENV.has_key? 'VERBOSE'
      head
    end
    
    def self.Insecure host
      HTTPHosts[host] = true
    end

    def insecure?
      HTTPHosts.has_key? host
    end

    def local?
      LocalAddress.member? env['SERVER_NAME']
    end

    # URI -> storage node(s) -> RDF graph -> HTTP response
    def nodeResponse
      return fileResponse if node.file? # static node response
      qs = query_values || {}           # query arguments
      timeMeta                          # find temporally-adjacent node pointers

      nodes = (if node.directory?       # multi-node container
               if qs.has_key? 'f'       # FIND name
                 summarize = true
                 q = qs['f']
                 `find #{shellPath} -iname #{Shellwords.escape q}`.lines.map{|p|('/' + p.chomp).R} unless qs['f'].empty? || path == '/'
               elsif qs.has_key? 'find' # FIND substring
                 summarize = true
                 q = '*' + qs['find'] + '*'
                 `find #{shellPath} -iname #{Shellwords.escape q}`.lines.map{|p|('/' + p.chomp).R} unless qs['find'].empty? || path == '/'
               elsif (qs.has_key?('Q') || qs.has_key?('q')) && path != '/'
                 env[:grep] = true      # GREP
                 q = qs['Q'] || qs['q']
                 args = q.shellsplit rescue q.split(/\W/)
                 case args.size
                 when 0
                   return []
                 when 2 # two unordered terms
                   cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -il #{Shellwords.escape args[1]}"
                 when 3 # three unordered terms
                   cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -il #{Shellwords.escape args[2]}"
                 when 4 # four unordered terms
                   cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -ilZ #{Shellwords.escape args[2]} | xargs -0 grep -il #{Shellwords.escape args[3]}"
                 else # N ordered terms
                   pattern = args.join '.*'
                   cmd = "grep -ril -- #{Shellwords.escape pattern} #{shellPath}"
                 end
                 `#{cmd} | head -n 1024`.lines.map{|path| ('/' + path.chomp).R }
               else                     # LS
                 ls = [self]
                 ls.concat((self + '.*').R.glob) if path[-1] != '/'
                 ls
               end
              else
                if uri.match GlobChars  # GLOB - parametric
                  summarize = true
                  env[:grep] = true if env && qs.has_key?('q')
                  glob
                else                    # GLOB - graph-storage
                  (self + '.*').R.glob
                end
               end).flatten.compact.uniq.map{|n|n.R env}

      if nodes.size==1 && nodes[0].ext == 'ttl' && selectFormat == 'text/turtle'
        nodes[0].fileResponse           # static graph-node response
      else                              # graph node(s) response
        nodes = nodes.map &:summary if summarize && !qs.has_key?('full')
        nodes.map &:loadRDF
        graphResponse
      end
    end

    def notfound; [404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def OPTIONS
      if AllowedHosts.has_key?(host) || POSThost.match?(host)
        self.OPTIONSthru
      else
        env[:deny] = true
        [204, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => 'authorization, content-type, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-hostname, x-lib-version, x-locale, x-requested-with',
               'Access-Control-Allow-Origin' => allowedOrigin},
         []]
      end
    end

    def OPTIONSthru
      r = HTTParty.options uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    def self.Populate host, lambda
      Populator[host] = lambda
    end

    def self.POST host, lambda
      HostPOST[host] = lambda
    end

    def POST
      if handler = HostPOST[host]
        handler[self]
      elsif AllowedHosts.has_key?(host) || POSThost.match?(host)
        self.POSTthru
      else
        denyPOST
      end
    end

    def POSTthru
      r = HTTParty.post uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    def HTTP.print_body head, body
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

    def HTTP.print_header header
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
               'Access-Control-Allow-Headers' => 'authorization, content-type, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-hostname, x-lib-version, x-locale, x-requested-with',
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
        puts "WARNING query key #{k} has multiple vals: #{v.join ' '}, using #{v[0]}" if v.class == Array && v.size > 1
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def selectFormat default = 'text/html'
      return default unless env && env.has_key?('HTTP_ACCEPT') # default via no specification

      index = {} # q -> format map
      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats selected in descending q-value order
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with 🐢-preference
          return default if f == '*/*'                        # default via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF via writer definition
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF via writer definition

      default                                                 # default
    end

    def timeMeta
      n = nil # next page
      p = nil # prev page
      # date parts
      dp = []; ps = parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)
      case dp.length
      when 1 # Y
        year = dp[0]
        n = '/' + (year + 1).to_s
        p = '/' + (year - 1).to_s
      when 2 # Y-m
        year = dp[0]
        m = dp[1]
        n = m >= 12 ? "/#{year + 1}/#{01}" : "/#{year}/#{'%02d' % (m + 1)}"
        p = m <=  1 ? "/#{year - 1}/#{12}" : "/#{year}/#{'%02d' % (m - 1)}"
      when 3 # Y-m-d
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          p = (day-1).strftime('/%Y/%m/%d')
          n = (day+1).strftime('/%Y/%m/%d')
        end
      when 4 # Y-m-d-H
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          hour = dp[3]
          p = hour <=  0 ? (day - 1).strftime('/%Y/%m/%d/23') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour-1)))
          n = hour >= 23 ? (day + 1).strftime('/%Y/%m/%d/00') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour+1)))
        end
      end
      remainder = ps.empty? ? '' : ['', *ps].join('/')
      remainder += '/' if env['REQUEST_PATH'] && env['REQUEST_PATH'][-1] == '/'
      q = env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || ''
      env[:links][:prev] = p + remainder + q + '#prev' if p
      env[:links][:next] = n + remainder + q + '#next' if n
    end

    def upstreamUI; env[:UX] = true; self end
    def upstreamUI?
      env.has_key?(:UX) || ENV.has_key?('UX') || parts.member?('embed') || query_values&.has_key?('UX')
    end

    def writeFile o
      FileUtils.mkdir_p node.dirname
      File.open(fsPath,'w'){|f|f << o.force_encoding('UTF-8')}
      self
    end

  end
  include HTTP
end
