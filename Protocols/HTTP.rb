# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    AllowedHosts = {}
    CDNuser = {}
    CookieHosts = {}
    GlobChars = /[\*\{\[]/
    HostGET = {}
    HostPOST = {}
    HTTPHosts = {}
    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq
    LocalArgs = %w(allow view sort UX)
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Populator = {}
    Servers = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Suffixes = {
      'application/x-javascript' => '.js', 'audio/mpeg' => '.mp3',
      'image/x-icon' => '.ico', 'image/webp' => '.webp',
      'text/xml' => '.rss'}
    Internal_Headers = %w(base-uri connection gunk host links path-info query query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rdf remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software site-chrome transfer-encoding unicorn.socket upgrade-insecure-requests ux version via x-forwarded-for)

    # handlers
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.env[:query].has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.env[:query]['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.env[:query]['url']||r.env[:query]['q'])}, []]}
    NoGunk  = -> r {r.gunkURI && r.env[:query]['allow'] != ServerKey && r.deny || r.fetch}
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
      if r.qs.empty?                               # request without qs
        NoGunk[r].yield_self{|s,h,b|               # inspect response
          h.keys.map{|k|                           # strip qs from location
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                                 # cleaned response
      else                                         # request with qs
        [302, {'Location' => r.env['REQUEST_PATH']}, []] # redirect to path
      end}

    RootIndex = -> r {
      if r.path == '/' || r.path.match?(GlobChars)
        r.nodeRequest
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
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']              # only handle HTTP methods
      resource = RDF::URI('//'+env['SERVER_NAME']).join(env['REQUEST_PATH']).R env # instantiate request
      env[:base_uri] = resource                                                 # resource URI
      env[:referer] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}                                                           # response HEAD storage
      env[:links] = {}                                                          # response Link storage
      env[:query] = parseQs(env['QUERY_STRING'])                           # parse query
      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body| # dispatch

        ext = resource.path ? resource.ext.downcase : ''                   # log request
        mime = head['Content-Type'] || ''

        # highlight host on first-visit of this server run
        unless (Servers.has_key? env['SERVER_NAME']) || resource.env[:deny]
          Servers[env['SERVER_NAME']] = true
          print "\n➕ \e[1;7;32mhttps://" + env['SERVER_NAME'] + "\e[0m "
        end

        if resource.env[:deny]
          if %w(css eot otf ttf woff woff2).member?(ext) || resource.path.match?(/204$/)
            print "🛑"
          else
            print "\n" + (env['REQUEST_METHOD'] == 'POST' ? "\e[31;7;1m📝 " : "🛑 \e[31;1m") + (env[:referer] ? ("\e[7m" + env[:referer] + "\e[0m\e[31;1m → ") : '') + (env[:referer] == resource.host ? '' : ('http://' + resource.host)) + "\e[7m" + resource.path + "\e[0m\e[31m" + resource.qs + "\e[0m "
          end

        # OPTIONS
        elsif env['REQUEST_METHOD'] == 'OPTIONS'
          print "\n🔧 \e[32;1m#{resource.uri}\e[0m "

        # POST
        elsif env['REQUEST_METHOD'] == 'POST'
          print "\n📝 \e[32;1m#{resource.uri}\e[0m "

        # non-content response
        elsif [301, 302, 303].member? status
          print "\nhttps:", resource.uri ," ➡️  ", head['Location'] # redirection
        elsif [204, 304].member? status
          print '✅'                    # up-to-date
        elsif status == 404
          print "\n❓ #{resource.uri} " # not found

        # content response
        elsif ext == 'css'                                       # stylesheet
          print '🎨'
        elsif ext == 'js' || mime.match?(/script/)               # script
          third_party = env[:referer] != resource.host
          print "\n📜 \e[36#{third_party ? ';7' : ''};1mhttps://" + resource.host + resource.path + "\e[0m "
        elsif ext == 'json' || mime.match?(/json/)               # data
          print "\n🗒 https://" + resource.host + resource.path + resource.qs + ' '
        elsif %w(gif jpeg jpg png svg webp).member?(ext) || mime.match?(/^image/)
          print '🖼️'                                              # image
        elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
          print '🔉'                                             # audio
        elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
          print '🎬'                                             # video
        elsif ext == 'ttl' || mime == 'text/turtle; charset=utf-8'
          print '🐢'                                             # turtle

        else # generic logger
          print "\n\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : (env['REQUEST_METHOD']+' ')) + (status == 200 ? '' : (status.to_s+' ')) +
                (env[:referer] ? (env[:referer] + ' → ') : '') + "https://" + env['SERVER_NAME'] + env['REQUEST_PATH'] + resource.qs + "\e[0m "
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

    def self.CDNexec host
      CDNuser[host] = true
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
                        env[:query]['allow'] = ServerKey
                        href = qs.match?(/campaign|[iu]tm_/) ? '?' : HTTP.qs(env[:query])
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{href}' style='color: #fff; font-size: 22em; font-weight: bold; text-decoration: none'>⌘</a></body></html>"]
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

      # cached results
      if (CacheExt - %w(html xml)).member?(ext.downcase) && !host.match?(DynamicImgHost)
        return R304 if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has static-data, return 304 response
        return fileResponse if node.file?                                           # server has static-data, return data
      end
      return nodeRequest if ENV.has_key? 'OFFLINE'                                                # offline, return cache

      # locator
      p = default_port? ? '' : (':' + env['SERVER_PORT'].to_s)
      u = '//'+host+p+path+(options[:suffix]||'')+(options[:query] ? HTTP.qs(options[:query]) : qs) # base locator
      primary  = ('http' + (insecure? ? '' : 's') + ':' + u).R env                                  # primary scheme
      fallback = ('http' + (insecure? ? 's' : '') + ':' + u).R env                                  # fallback scheme

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
      URI.open(uri, headers.merge({redirect: false})) do |response| print '🌍🌎🌏🌐'[rand 4]
        h = response.meta                                                 # upstream metadata
        if response.status.to_s.match? /206/                              # partial response
          h['Access-Control-Allow-Origin'] = allowedOrigin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                                       # part to downstream
        else
          body = HTTP.decompress h, response.read                         # decompress body
          format = h['content-type'].split(/;/)[0] if h['content-type']   # HTTP header -> format
          format ||= (xt = ext.to_sym; puts "WARNING no MIME for #{uri}"  # extension -> format
                      RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])
          static = fixedFormat? format
          body = Webize::HTML.degunk body,static if format == 'text/html' && !AllowedHosts.has_key?(host) # clean HTML
          formatExt = Suffixes[format] || Rack::Mime::MIME_TYPES.invert[format] || (puts "WARNING suffix undefined for #{format}";'') # MIME to suffix mapping
          suffix = formatExt == extension && '' || formatExt              # append MIME-suffix if incorrect or missing
          (fsPath + suffix).R.writeFile body                              # cache body
          (fsPath + '.' + Time.now.iso8601 + suffix).R.writeFile body if suffix == '.json' # cache body - version
          reader = RDF::Reader.for content_type: format                   # select reader
          reader.new(body,base_uri: env[:base_uri],noRDF: options[:noRDF]){|_| # instantiate reader
            (env[:repository] ||= RDF::Repository.new) << _ } if reader   # parse RDF
          return self if options[:intermediate]                           # intermediate fetch, return w/o HTTP-response
          saveRDF if reader; puts "no reader for " + format unless reader # store RDF
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}             # expose upstream metadata to downstream
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin     # CORS header
          env[:resp]['Set-Cookie'] = h['set-cookie'] if h['set-cookie'] && allowCookies?
          if static
            env[:resp]['Content-Length'] = body.bytesize.to_s             # size header
            [200, env[:resp], [body]]                                     # upstream doc
          else
            graphResponse                                                 # local doc
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
        options[:intermediate] ? self : nodeRequest
      when /403/ # Forbidden
        print "\n🚫403 " + uri + ' '
        options[:intermediate] ? self : nodeRequest
      when /404/ # Not Found
        print "\n❓ #{uri} "
        if options[:intermediate]
          self
        elsif upstreamUI?
          [404, (headers e.io.meta), [e.io.read]]
        else
          nodeRequest
        end
      when /410/ # Gone
        print "\n❌ " + uri + ' '
        options[:intermediate] ? self : nodeRequest
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
      return false if env[:query].has_key?('rdf') || env[:transform] || !format || format.match?(/atom|html|rss|xml/i)
      return true
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local?
        if %w{y year m month d day h hour}.member? parts[0]
          dateDir                   # timeline-segment redirection
        elsif path == '/mail'       # inbox to timeline-glob redirection
          [302, {'Location' => '/d/*/msg*?sort=date&view=table'}, []]
        elsif parts[0] == 'msg'     # Message-ID <> URI map
          id = parts[1]
          id ? MID2PATH[Rack::Utils.unescape_path id].R(env).nodeRequest : notfound
        elsif node.file?
          fileResponse              # local static data
        else
          unless !path || path == '/'
            dir = File.dirname path
            env[:links][:up] = dir + (dir[-1] == '/' ? '' : '/') + qs
          end
          timeMeta
          nodeRequest               # local transformable/graph data
        end
      elsif path.match? /^.gen(erate)?_?204$/ # connectivity check
        R204
      elsif path.match? /^\/\d\d\d\d\/\d\d\/\d\d\/\d\d\/$/ # hour-dir pagination of cached remote
        name = '*' + env['SERVER_NAME'].split('.').-(Webize::Plaintext::BasicSlugs).join('.') + '*'
        timeMeta
        env[:links][:time] = 'http://localhost:8000' + path + '*.ttl?view=table' if env['REMOTE_ADDR'] == '127.0.0.1'
        (path + name).R(env).nodeRequest
      elsif handler = HostGET[host] # host lambda
        Populator[host][self] if Populator[host] && !join('/').R.node.exist?
        handler[self]
      elsif host.match? CDNhost     # CDN content-pool
        if AllowedHosts.has_key?(host) || env[:query]['allow'] == ServerKey ||
           CDNuser.has_key?(env[:referer]) ||
           ((CacheExt - %w(html js)).member?(ext.downcase) && !path.match?(Gunk))
          fetch                     # allowed CDN content
        else
          deny                      # blocked CDN content
        end
      elsif gunk?                   # blocked content
        deny
      else
        dir = File.dirname path
        env[:links][:up] = dir + (dir == '/' ? '' : '/') + qs unless !path || path == '/'
        fetch                       # generic remote resource
      end
    end

    alias_method :get, :fetch

    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
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
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => env[:base_uri], :standard_prefixes => true
        end}
    end

    def gunk?
      return false if env[:query]['allow'] == ServerKey
      gunkTag? || gunkURI
    end

    def gunkDomain?
      return false unless host
      return false if AllowedHosts.has_key?(host) || HostGET.has_key?(host) || host.match?(CDNhost)
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

    # headers formatted and filtered for export w/ capability check
    def headers hdrs = nil
      head = {} # header storage

      (hdrs || env || {}).map{|k,v| # raw headers
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|k| # strip HTTP prefix
          if %w{cl dfe id spf utc xsrf}.member? k # acronyms
            k = k.upcase       # acronymize
          else
            k[0] = k[0].upcase # capitalize
          end
          k }.join(underscored ? '_' : '-')
        key = key.downcase if underscored

        # set values
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless Internal_Headers.member?(key.downcase)}

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

    def nodeRequest
      nodes = (if node.directory?                # directory:
               if env[:query].has_key? 'f'       # FIND full case-insensitive match
                 summarize = true
                 q = env[:query]['f']
                 `find #{shellPath} -iname #{Shellwords.escape q}`.lines.map{|p|('/' + p.chomp).R} unless env[:query]['f'].empty? || path == '/'
               elsif env[:query].has_key? 'find' # FIND substring match
                 summarize = true
                 q = '*' + env[:query]['find'] + '*'
                 `find #{shellPath} -iname #{Shellwords.escape q}`.lines.map{|p|('/' + p.chomp).R} unless env[:query]['find'].empty? || path == '/'
               elsif (env[:query].has_key?('Q') || env[:query].has_key?('q')) && path != '/'
                 env[:grep] = true               # GREP
                 q = env[:query]['Q'] || env[:query]['q']
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
               else                                                    # LS
                 ls = [self]
                 ls.concat((self + '.*').R.glob) if path[-1] != '/'
                 ls
               end
              else                                                     # files:
                if uri.match GlobChars                                 # GLOB - parametric
                  summarize = true
                  env[:grep] = true if env && env[:query].has_key?('q')
                  glob
                else                                                   # GLOB - default graph-data
                  (self + '.*').R.glob
                end
               end).flatten.compact.uniq.map{|n|n.R env}
      if nodes.size==1 && nodes[0].ext == 'ttl' && selectFormat == 'text/turtle'
        nodes[0].fileResponse # nothing to transform. return static data
      else                    # graph data
        nodes = nodes.map &:summary if summarize
        nodes.map &:loadRDF
        graphResponse
      end
    end

    def notfound
      timeMeta # nearby nodes may exist, add pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

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
      # request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read
      # response
      r = HTTParty.options url, :headers => head, :body => body
      h = headers r.headers
      [r.code, h, [r.body]]
    end

    # String -> Hash
    def HTTP.parseQs querystring
      if querystring
        table = {}
        querystring.split(/&/).map{|e|
          k, v = e.split(/=/,2).map{|x|CGI.unescape x}
          table[k] = v if k}
        table
      else
        {}
      end
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
      # origin request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read
      # origin response
      r = HTTParty.post url, :headers => head, :body => body
      h = headers r.headers
      [r.code, h, [r.body]]
    end

    def HTTP.print_body head, body
      type = head['Content-Type'] || head['content-type']
      puts type
      puts case type
           when 'application/x-www-form-urlencoded'
             form = parseQs body
             ::JSON.pretty_generate(if form['message']
                                     ::JSON.parse form['message']
                                    else
                                     form
                                    end)
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
      puts '_'*40
      header.map{|k, v| puts [k, v.to_s].join "\t"}
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
      # request
      url = 'https://' + host + path + qs
      body = env['rack.input'].read
      puts "PUT #{url}", body
      # response
      r = HTTParty.put url, :headers => headers, :body => body
      [r.code, (headers r.headers), [r.body]]
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' unless h
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.join("&")
    end

    def querystring
      if env
        if env[:query]                                           # parsed query?
          q = env[:query].dup                                    # read query
          LocalArgs.map{|a| q.delete a }                         # eat internal args
          return q.empty? ? '' : HTTP.qs(q)                      # stringify
        elsif env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query-string in environment
          return '?' + env['QUERY_STRING']
        end
      end
      query && !query.empty? && ('?' + query) || ''              # query-string in URI
    end
    alias_method :qs, :querystring

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
      env.has_key?(:UX) || ENV.has_key?('UX') ||      # environment
      parts.member?('embed') || env[:query].has_key?('UX') # URL parameter
    end

    def writeFile o
      FileUtils.mkdir_p node.dirname
      File.open(fsPath,'w'){|f|f << o.force_encoding('UTF-8')}
      self
    end

  end
  include HTTP
end
