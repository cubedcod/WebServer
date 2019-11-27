# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include POSIX
    include URIs

    AllowedHosts = {}
    CookieHost = {}
    HostGET = {}
    HostPOST = {}
    LocalArgs = %w(allow view sort UX)
    Servers = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join)[0..7]

    # base HTTP methods
    Methods = {
      'GET'     => :GETresource,
      'HEAD'    => :HEAD,
      'OPTIONS' => :OPTIONS,
      'POST'    => :POSTresource}

    # handler lambdas
    Desktop = -> r {NoGunk[r.desktopUI]}
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.env[:query].has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.env[:query]['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.env[:query]['url']||r.env[:query]['q'])}, []]}
    Icon    = -> r {r.env[:deny] = true; [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}
    JS = -> r, pattern {(r.env['HTTP_REFERER']&.match(pattern) && NoGunk || NoJS)[r]}
    NoGunk  = -> r {r.gunkURI ? r.deny : r.fetch}
    NoJS    = -> r {r.ext=='js' ? r.deny : NoGunk[r]} # TODO inspect response content-type
    NoQuery = -> r {r.qs.empty? ? r.fetch : [301, {'Location' => r.env['REQUEST_PATH']}, []]}
    RootIndex = -> r { r.chrono_sort if r.parts.size == 1; r.path == '/' ? r.cachedGraph : NoGunk[r]}

    # canned responses
    R204 = [204, {}, []]
    R304 = [304, {}, []]

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      @cookies || AllowedHosts.has_key?(host) || CookieHost.has_key?(host)
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

    def bindEnv e
      @env = e
      self
    end

    def cachePath format = nil
      p = path || '/'
      p += 'index' + (Rack::Mime::MIME_TYPES.invert[format] || '.bin') if format && p[-1] == '/' # find format-extension
      (hostpath + p).R env
    end

    def cachedGraph; nodeResponse cachePath end

    def self.call env
      return [405,{},[]] unless m=Methods[env['REQUEST_METHOD']] # find method-handler
      path = Pathname.new(env['REQUEST_PATH']).expand_path.to_s  # evaluate path expression
      path+='/' if env['REQUEST_PATH'][-1]=='/' && path[-1]!='/' # preserve trailing slash
      resource = ('//' + env['SERVER_NAME'] + path).R env.merge( # instantiate request w/ blank response fields
       {resp:{}, links:{}, query: parseQs(env['QUERY_STRING'])}) # parse query
      resource.send(m).yield_self{|status, head, body|           # dispatch request

        verbose = resource.verbose?                              # log request
        ext = resource.ext.downcase
        mime = head['Content-Type'] || ''

        if verbose
          print "\n"
          puts env['REQUEST_METHOD'] + ' REQUEST'
          HTTP.print_header env
          puts env['REQUEST_METHOD'] + ' RESPONSE ' + status.to_s
          HTTP.print_header head
        end

        # highlight host on first encounter
        unless (Servers.has_key? env['SERVER_NAME']) || resource.env[:deny]
          Servers[env['SERVER_NAME']] = true
          print "\n➕ \e[1;7;32mhttps://" + env['SERVER_NAME'] + "\e[0m "
        end

        if resource.env[:deny]
          if %w(css eot otf ttf woff woff2).member?(ext) || path.match?(/204$/)
            print "🛑"
          else
            referer_host = env['HTTP_REFERER'] && env['HTTP_REFERER'].R.host
            print "\n" + (env['REQUEST_METHOD'] == 'POST' ? "\e[31;7;1m📝 " : "🛑 \e[31;1m") + (referer_host ? ("\e[7m" + referer_host + "\e[0m\e[31;1m → ") : '') + (referer_host == resource.host ? '' : resource.host) + "\e[7m" + resource.path + "\e[0m\e[31m" + resource.qs + "\e[0m "
            resource.env[:query]&.map{|k,v| print "\n\e[7m#{k}\e[0m\t#{v}"} if verbose
          end

        # OPTIONS
        elsif env['REQUEST_METHOD'] == 'OPTIONS'
          print "\n🔧 \e[32;1m#{resource.uri}\e[0m "

        # POST
        elsif env['REQUEST_METHOD'] == 'POST'
          print "\n📝 \e[32;1m#{resource.uri}\e[0m "

        # non-content response
        elsif [301, 302, 303].member? status
          print "\nhttps:", resource.uri ," ➡️ ", head['Location'] # redirection
        elsif [204, 304].member? status
          print '✅'                    # up-to-date
        elsif status == 404
          print "\n❓ #{resource.uri} " # not found

        # content response
        elsif ext == 'css'                                       # stylesheet
          print '🎨'
        elsif ext == 'js' || mime.match?(/script/)               # script
          print "\n📜\e[36;1m https://" + resource.host + "\e[7m" + resource.path + "\e[0m "
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

        else # generic logging
          print "\n\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : (env['REQUEST_METHOD']+' ')) + (status == 200 ? '' : (status.to_s+' ')) +
                (env['HTTP_REFERER'] ? ((env['HTTP_REFERER'].R.host||'') + ' → ') : '') + "https://" + env['SERVER_NAME'] + env['REQUEST_PATH'] + resource.qs + "\e[0m "
        end

        # response
        [status, head, body]}
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

    def CDN?; host.match? CDNhost end

    def self.Cookies host
      CookieHost[host] = true
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

    def dateMeta
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
      env[:links][:prev] = p + remainder + q + '#prev' if p && p.R.exist?
      env[:links][:next] = n + remainder + q + '#next' if n && n.R.exist?
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
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{href}' style='color: #fff; font-size: 22em; text-decoration: none; font-weight: normal'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      env[:deny] = true
      hd = headers
      HTTP.print_body hd, HTTP.decompress(hd, env['rack.input'].read.force_encoding('UTF-8')) if verbose?
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    def desktopUI; upstreamUI; desktopUA end

    def desktopUA; env['HTTP_USER_AGENT'] = DesktopUA; self end

    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/
      if entities && entities.include?(env[:resp]['ETag'])
        R304                                     # unmodified resource
      else
        body = generator ? generator.call : self # generate resource
        if body.class == WebResource             # resource reference
          Rack::File.new(nil).serving(Rack::Request.new(env), body.relPath).yield_self{|s,h,b|
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

    # fetch node from remote or local cache
    def fetch options=nil
      options ||= {}

      # cache hits
      if (CacheExt - %w(html)).member? ext.downcase                                                   # request HTML updates
        return R304 if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE')     # client has static-data, return 304 response
        return cachePath.fileResponse if cachePath.file?                                              # server has static-data, return data
      end
      return cachedGraph if offline?                                                                  # offline, return cache

      # locator
      u = '//'+hostname+path+(options[:suffix]||'')+(options[:query] ? HTTP.qs(options[:query]) : qs) # base locator
      primary  = ((options[:scheme] || 'https').to_s + ':' + u).R env                                 # primary scheme
      fallback = ((options[:scheme] ? 'https' : 'http') + ':' + u).R env                              # fallback scheme

      # fetch, HTTPS with HTTP fallback
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
      when 'OpenURI::HTTPRedirect'
        fallback.fetchHTTP options
      when 'RuntimeError'
        fallback.fetchHTTP options
      when 'SocketError'
        fallback.fetchHTTP options
      else
        raise
      end
    end

    def fetchHTTP options={}
      open(uri, headers.merge({redirect: false})) do |response| print '🌍🌎🌏🌐'[rand 4]
        h = response.meta; HTTP.print_header h if verbose?                # response header

        if response.status.to_s.match? /206/                              # partial body
          [206, h, [response.read]]                                       # return part
        else

          # body
          body = HTTP.decompress h, response.read                         # decompress body

          # format
          format = h['content-type'].split(/;/)[0] if h['content-type']   # HTTPheader explicit format
          format ||= (xt = ext.to_sym; puts "WARNING no MIME for #{uri}"  # extension -> format map
           RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])

          # read body
          reader = RDF::Reader.for content_type: format
          reader.new(body, {base_uri: self, noRDF: options[:noRDF]}){|_|
            (env[:repository] ||= RDF::Repository.new) << _ } if reader

          cachePath(format).write body if CacheExt.member? ext.downcase   # cache update

          return self if options[:intermediate]                           # intermediate fetch - no direct HTTP caller

          # upstream metadata
          %w(Access-Control-Allow-Origin
             Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}
          env[:resp]['Set-Cookie'] = h['set-cookie'] if h['set-cookie'] && allowCookies?

          # local metadata
          indexRDF
          env[:resp]['Content-Length'] = body.bytesize.to_s

          # HTTP response
          (fixedFormat? format) ? [200,env[:resp],[body]] : graphResponse
        end
      end
    rescue Exception => e
      case e.message
      when /300/ # Multiple Choices
        [300, (headers e.io.meta), [e.io.read]]
      when /30[12378]/ # Relocated
        dest = e.io.meta['location'].R
        if (dest.path || '/') == (path || '/') && dest.host == host && dest.scheme != scheme # directed to fallback scheme
          raise
        else
          [302, {'Location' => dest.uri}, []]
        end
      when /304/ # Not Modified
        R304
      when /401/ # Unauthorized
        print "\n🚫401 " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /403/ # Forbidden
        print "\n🚫403 " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /404/ # Not Found
        options[:intermediate] ? self : cachedGraph
      when /410/ # Gone
        print "\n❌ " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /500/ # upstream error
        [500, (headers e.io.meta), [e.io.read]]
      when /503/
        @cookies = true
        hdrs = e.io.meta
        head = headers hdrs
        body = e.io.read
        puts 503 ; HTTP.print_header hdrs; puts '^^^^vvvv' ;  HTTP.print_header head ; puts body
        [200, head, [body]]
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def findNodes
      return dir.findNodes if name == 'index'
      (if directory?                                           # directory?
       if env[:query].has_key?('f') && path != '/'             # FIND
          find env[:query]['f'] unless env[:query]['f'].empty? #  pedantic
       elsif env[:query].has_key?('find') && path != '/'       #  easy mode
          find '*' + env[:query]['find'] + '*' unless env[:query]['find'].empty?
       elsif (env[:query].has_key?('Q') || env[:query].has_key?('q')) && path != '/'
         env[:grep] = true                                     # GREP
         grep
       else                                                    # LS
         [self]
       end
      else                                                     # file(s)
        if uri.match GlobChars         # parametric GLOB
          env[:grep] = true if env && env[:query].has_key?('q')
          glob
        else                           # default GLOB
          files = (self + '.*').R.glob #  basename + format
          files = (self + '*').R.glob if files.empty? # path prefix
          [self, files]                # exact match
        end
       end).flatten.compact.uniq.select(&:exist?).map{|n|n.bindEnv env}
    end

    # allow rewrite if explicit-allow, untyped, Atom/RSS feed, or HTML and not using upstream UI
    def fixedFormat? format = nil
      return true if upstreamUI?
      return false if env[:transformable] || !format || format.match?(/\/(atom|html|rss|xml)/i)
      return true
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end
    alias_method :get, :fetch

    def GETresource
      if local?                 # local resource:
        if %w{y year m month d day h hour}.member? parts[0]
          dateDir                  # time-segment redirect
        elsif path == '/log'       # log handler
          localLog
        elsif path == '/mail'      # inbox redirect
          [302,{'Location' => '/d/*/msg*?head&sort=date&view=table'},[]]
        elsif file?
          fileResponse             # local static-data
        elsif directory? && qs.empty? && (index = (self + 'index.html').R env).exist? && selectFormat == 'text/html'
          index.fileResponse       # local static directory-index
        else                       # local graph-data
          localGraph
        end
      elsif handler = HostGET[host] # host handler
        handler[self]
      elsif self.CDN?               # content-pool handler
        if ENV.has_key? 'BARNDOOR'
          fetch
        else
          extension = ext.downcase
          CacheExt.member?(extension) && extension != 'js' && !gunkURI && fetch || deny
        end
      elsif gunkHost || gunkURI     # junk handler
        deny
      elsif path.match? /^\/\d\d\d\d\/\d\d\/\d\d\/\d\d\/$/ # cache-timeslice handler
        name = '*' + env['SERVER_NAME'].split('.').-(Webize::Plaintext::BasicSlugs).join('.') + '*'
        nodeResponse (path + name)
      else
        env[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs unless !path || path == '/'
        fetch                      # remote resource
      end
    end

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
          rdfDocument format
        end}
    end

    def gunkHost
      return false if ENV.has_key?('BARNDOOR') || (env && env[:query]['allow'] == ServerKey) || AllowedHosts.has_key?(host)
      env && env.has_key?('HTTP_GUNK')
    end

    def gunkURI
      return false if ENV.has_key?('BARNDOOR') || (env && env[:query]['allow'] == ServerKey)
      ('/' + hostname + (env && env['REQUEST_URI'] || path || '/')).match? Gunk
    end

    def HEAD
      send(Methods['GET']).yield_self{|s,h,_| [s,h,[]] } # status-code & header
    end

    # header formatted and filtered
    def headers hdrs = nil
      head = {} # header storage

      (hdrs || env || {}).map{|k,v| # raw headers
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|k| # eat Rack HTTP_ prefix
          if %w{cl dfe id spf utc xsrf}.member? k # acronyms
            k = k.upcase       # acronymize
          else
            k[0] = k[0].upcase # capitalize
          end
          k }.join(underscored ? '_' : '-')
        key = key.downcase if underscored

        # set external header keys & values
        head[key] = v.to_s unless %w{connection gunk host links path-info query query-modified query-string
rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version
remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software
transfer-encoding unicorn.socket upgrade-insecure-requests ux version via x-forwarded-for}.member?(key.downcase)}

      # Cookie
      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'

      # Referer
        head.delete 'Referer'
      end
      if env && env['SERVER_NAME']
        case env['SERVER_NAME']
        when /wsj\.com$/
          head['Referer'] = 'http://drudgereport.com/'
        when /youtube.com$/
          head['Referer'] = 'https://www.youtube.com/'
        end
      end

      # User-Agent
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st'
      head.delete 'User-Agent' if host == 't.co'

      head # output header
    end

    # node metadata/RDF -> RDF::Repository
    def load options = {}
      env[:repository] ||= RDF::Repository.new # graph
      stat options                             # read filesystem-metadata
      return self unless file?
      options[:base_uri] ||= self              # base-URI
      options[:format]  ||= formatHint         # URI-derived format hint
      env[:repository].load relPath, options   # read file
      self                                     # node w/ Repository reference
    end

    def local?; LocalAddr.member?(env['SERVER_NAME']) || ENV['SERVER_NAME'] == env['SERVER_NAME'] end

    def localGraph
      env[:links][:turtle] = (path[-1] == '/' ? 'index' : name) + '.ttl'
      env[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs unless !path || path == '/'
      dateMeta
      nodeResponse
    end

    def localLog
      `tail -n 10000 ../web.log | grep '.js '`.each_line{|l| puts l }
    end

    def nodeResponse fs_base=self
      nodes = fs_base.R(env).findNodes
      if nodes.size==1 && nodes[0].ext=='ttl' && selectFormat=='text/turtle'
        nodes[0].fileResponse # nothing to merge or transform. return static node
      else                    # merge and/or transform
        nodes.map{|node|
          options = fs_base == self ? {} : {base_uri: (join node.relFrom fs_base)}
          node.load options}
        graphResponse
      end
    end

    def notfound
      dateMeta # nearby nodes may exist, add pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def OPTIONS
      if AllowedHosts.has_key?(host) || ENV.has_key?('BARNDOOR')
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
      body = env['rack.input'].read
      # response
      r = HTTParty.options url, :headers => headers, :body => body
      [r.code, r.headers, [r.body]]
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

    def self.POST host, lambda
      HostPOST[host] = lambda
    end

    def POSTresource
      if handler = HostPOST[host]
        handler[self]
      elsif AllowedHosts.has_key?(host) || ENV.has_key?('BARNDOOR')
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

      if verbose?
        puts "POST BODY:"
        HTTP.print_body head, body
      end

      # origin response
      r = HTTParty.post url, :headers => head, :body => body
      code = r.code
      head = r.headers
      body = r.body
      head.delete 'connection'
      head.delete 'transfer-encoding'

      if verbose?
        puts "RESPONSE HEAD:"
        HTTP.print_header head
        if body
          puts "RESPONSE BODY:"
          HTTP.print_body head, (HTTP.decompress head, body)
        end
      end
      [code, head, [body]]
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
      header.map{|k,v|
      puts       [k,v].join "\t"}
      puts " "
    end

    def PUT
      env[:deny] = true
      [202,{},[]]
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
          q = env[:query].dup                                    # load query
          LocalArgs.map{|a| q.delete a }                         # eat internal args
          return q.empty? ? '' : HTTP.qs(q)                      # stringify
        elsif env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # query-string in environment
          return '?' + env['QUERY_STRING']
        end
      end
      query && !query.empty? && ('?' + query) || ''              # query-string in URI
    end
    alias_method :qs, :querystring

    def stat options = {}
      graph = env[:repository] ||= RDF::Repository.new
      options[:base_uri] ||= self
      subject = options[:base_uri].R

      if node.directory?
        subject = subject.to_s[-1] == '/' ? subject : (subject+'/')                          # container URI
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Container').R)
        node.children.map{|n|
          name = n.basename.to_s
          name = n.directory? ? (name + '/') : name.sub(GraphExt, '')                        # contained-resource URI
          graph << (RDF::Statement.new subject,(W3+'ns/ldp#contains').R,subject.join(name))} # containment triple
      elsif node.file?
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/posix/stat#File').R)
        graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)        # node size
      end

      if mtime = node.stat.mtime
        graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#mtime').R, mtime.to_i)      # node mtime
        graph << (RDF::Statement.new subject, Date.R, mtime.iso8601)
      end

      graph << (RDF::Statement.new subject, Title.R, basename)                               # node name

      self
    end

    def selectFormat default='text/html'
      return 'text/turtle' if ext == 'ttl'
      return default unless env && env.has_key?('HTTP_ACCEPT')
      index = {}
      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats in descending q-value order
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with turtle-preference
          return default if f == '*/*'                        # HTML via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF

      default                                                 # HTML via default
    end

    def upstreamUI;  env[:UX] = true; self end
    def upstreamUI?
      env.has_key?(:UX)  ||      # per-request setting
      ENV.has_key?('UX') ||      # global setting
      env[:query].has_key?('UX') # query parameter
    end

    def verbose?; ENV.has_key? 'VERBOSE' end

  end
  include HTTP
end
