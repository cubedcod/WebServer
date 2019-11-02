# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include POSIX
    include URIs
    AllowedHosts = {}
    BaseMeta = %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag Set-Cookie)
    CookieHost = {}
    HostGET = {}
    HostPOST = {}
    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq
    LocalArgs = %w(allow view sort UX)
    Methods = {'GET' => :GETresource, 'HEAD' => :HEAD, 'OPTIONS' => :OPTIONS, 'POST' => :POSTresource}
    NoTransform = /^(application|audio|font|image|text\/(css|(x-)?javascript|proto)|video)/
    Servers = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join)[0..7]

    # handler lambdas
    Desktop = -> r {r.gunkURI ? r.deny : r.desktopUI.fetch}
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.env[:query].has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.env[:query]['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.env[:query]['url']||r.env[:query]['q'])}, []]}
    Icon    = -> r {r.env[:deny] = true; [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}
    NoGunk  = -> r {r.gunkURI ? r.deny : r.fetch}
    NoJS    = -> r {(r.gunkURI || r.ext=='js') ? r.deny : r.fetch}
    NoQuery = -> r {r.qs.empty? ? r.fetch : [301, {'Location' => r.env['REQUEST_PATH']}, []]}
    RootIndex = -> r {r.path=='/' ? r.cachedGraph : NoGunk[r]}

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowContent?
      return false if gunkURI
      return true if AV.member? ext.downcase           # media file
      return true if ext == 'js' && ENV.has_key?('JS') # executable
      false
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

    def cachePath; (hostpath + path).R env end

    def cachedGraph; nodeResponse cachePath end

    def self.call env
      return [405,{},[]] unless m=Methods[env['REQUEST_METHOD']] # look up method handler
      path = Pathname.new(env['REQUEST_PATH']).expand_path.to_s  # evaluate path expression,
      path+='/' if env['REQUEST_PATH'][-1]=='/' && path[-1]!='/' # preserving trailing slash
      resource = ('//' + env['SERVER_NAME'] + path).R env.merge( # instantiate request w/ blank response fields
       {resp:{}, links:{}, query: parseQs(env['QUERY_STRING'])}) # parse query
      resource.send(m).yield_self{|status, head, body|           # dispatch request
        ext = resource.ext.downcase
        mime = head['Content-Type'] || ''
        verbose = resource.verbose?                              # log request
        if resource.env[:deny]
          if %w(css eot otf ttf woff woff2).member?(ext) #|| QuietGunk.member?(resource.basename)
            print "🛑"
          elsif path.match? /204$/
            print "🛑"                                           # no content
          else
            referer_host = env['HTTP_REFERER'] && env['HTTP_REFERER'].R.host
            print "\n" + (env['REQUEST_METHOD'] == 'POST' ? "\e[31;7;1m📝 " : "🛑 \e[31;1m") + (referer_host ? ("\e[7m" + referer_host + "\e[0m\e[31;1m → ") : '') + (referer_host == resource.host ? '' : resource.host) + "\e[7m" + resource.path + "\e[0m\e[31m" + resource.qs + "\e[0m "
            resource.env[:query]&.map{|k,v|
              print "\n\e[7m#{k}\e[0m\t#{v}"} if verbose         # deny
          end
        elsif env['REQUEST_METHOD'] == 'OPTIONS'
          print "\n🔧 \e[32;1;7m #{resource.uri}\e[0m "          # OPTIONS
        elsif env['REQUEST_METHOD'] == 'POST'
          print "\n📝 \e[32;1;7m #{resource.uri}\e[0m "          # POST
        elsif [301, 302, 303].member? status
          print "\n➡️ ",head['Location']                          # redirected
        elsif [204, 304].member? status
          print '✅'                                             # up-to-date
        elsif status == 404
          print "\n❓ " + resource.uri + ' '                     # not found
        elsif !Servers.has_key? env['SERVER_NAME']
          Servers[env['SERVER_NAME']] = true                     # new host
          print "\n➕ \e[1;32mhttps://" + env['SERVER_NAME'] + "\e[7m" + resource.path + "\e[0m "
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
        else
          print "\n\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : (env['REQUEST_METHOD']+' ')) + (status == 200 ? '' : (status.to_s+' ')) +
                (env['HTTP_REFERER'] ? ((env['HTTP_REFERER'].R.host||'') + ' → ') : '') +
                "https://" + env['SERVER_NAME'] + env['REQUEST_PATH'] + resource.qs + "\e[0m "
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
      type, content = if ext == 'js' || type == :script
                        source = SiteDir.join 'alternatives/' + host + path
                        ['application/javascript', source.exist? ? source.read : '//']
                      elsif %w(gif png).member?(ext) || type == :image
                        ['image/gif', SiteGIF]
                      elsif ext == 'json' || type == :json
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='?allow=#{ServerKey}' style='color: #fff; font-size: 22em; text-decoration: none'>⌘</a></body></html>"]
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
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/ # client entities
      if entities && entities.include?(env[:resp]['ETag']) # client has entity
        [304, {}, []]                            # unmodified
      else
        body = generator ? generator.call : self # call generator
        if body.class == WebResource             # resource reference?
          Rack::File.new(nil).serving(Rack::Request.new(env), body.relPath).yield_self{|s,h,b|
            if s == 304
              [s, {}, []]                          # unmodified
            else                                   # Rack file-handler
              h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type'] == 'application/javascript'
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]         # file-backed entity
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

    # fetch resource
    def fetch options = {}
      if AV.member? ext.downcase
        return [304,{},[]] if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has static-media, return 304
        return cachePath.fileResponse if cachePath.file?                                                 # server has static-media, respond with it
      end
      return cachedGraph if offline?                                                                     # offline, cache of prior fetch
      u = '//'+hostname+path+(options[:suffix]||'')+(options[:query] ? (HTTP.qs options[:query]) : qs)   # base locator
      primary  = ((options[:scheme] || 'https').to_s + ':' + u).R env                                    # primary-scheme locator
      fallback = ((options[:scheme] ? 'https' : 'http') + ':' + u).R env                                 # fallback-scheme locator
      primary.fetchHTTP options                           # fetch
    rescue Exception => e                                 # fetch failure
      case e.class.to_s
      when 'OpenURI::HTTPRedirect'                        # redirected
        if (fallback.uri.index e.io.meta['location']) == 0
          fallback.fetchHTTP options                      # follow to fallback
        elsif options[:intermedate]                       # non-HTTP caller?
          puts "RELOC #{uri} -> #{e.io.meta['location']}" # alert caller of new location
          e.io.meta['location'].R(env).fetchHTTP options  # follow redirect for caller
        else
          redirect e.io.meta['location']                  # HTTP caller can follow at discretion
        end
      when 'Errno::ECONNREFUSED'
        fallback.fetchHTTP options
      when 'Errno::ECONNRESET'
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

    # fetch over HTTP
    def fetchHTTP options = {}
      open(uri, headers.merge({redirect: false})) do |response|           # fetch
        h = response.meta; print '🌍🌎🌏🌐'[rand 4]                       # metadata
        if response.status.to_s.match? /206/                              # partial body
          [206, h, [response.read]]                                       # return part
        else                                                              # complete body
          body = HTTP.decompress h, response.read                         # decode body

          format = h['content-type'].split(/;/)[0] if h['content-type']   # format
          format ||= (xt=ext.to_sym; puts "WARNING no MIME for #{uri}"    # extension -> format
                      RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])
          format = 'text/nfo' if ext=='nfo' && format.match?(/^text.plain/)

          reader = RDF::Reader.for content_type: format                   # find RDF reader
          reader.new(body, {base_uri: self, noRDF: options[:noRDF]}){|_|  # instantiate reader
            (env[:repository] ||= RDF::Repository.new) << _ } if reader   # extract RDF
          cachePath.write body if AV.member? ext.downcase                 # cache if static-media
          options[:intermediate] ? (return self) : index                  # return if intermediate fetch

          BaseMeta.map{|k|env[:resp][k]||=h[k.downcase] if h[k.downcase]} # upstream metadata
          env[:resp]['Content-Length'] = body.bytesize.to_s               # content-length
          (fixedFormat? format) ? [200,env[:resp],[body]] : graphResponse # HTTP response
        end
      end
    rescue Exception => e
      case e.message
      when /300/ # Multiple Choices
        [300, e.io.meta, [e.io.read]]
      when /304/ # Not Modified
        [304, {}, []]
      when /401/ # Unauthorized
        print "\n🚫 " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /403/ # Forbidden
        print "\n🚫 " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /404/ # Not Found
        options[:intermediate] ? self : cachedGraph
      when /410/ # Gone
        print "\n❌ " + uri + ' '
        options[:intermediate] ? self : cachedGraph
      when /500/ # upstream error
        [500, e.io.meta, [e.io.read]]
      when /503/
        [200, e.io.meta, [e.io.read]]
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
      (if directory?                                           # directory:
       if env[:query].has_key?('f') && path != '/'             # FIND
          find env[:query]['f'] unless env[:query]['f'].empty? # exact find
       elsif env[:query].has_key?('find') && path != '/'       # easy find
          find '*' + env[:query]['find'] + '*' unless env[:query]['find'].empty?
       elsif (env[:query].has_key?('Q') || env[:query].has_key?('q')) && path != '/'
         env[:grep] = true                                     # GREP
         grep
       else                                                    # LS
         [self]
       end
      else                                                     # file(s):
        if uri.match GlobChars         # parametric GLOB
          env[:grep] = true if env && env[:query].has_key?('q')
          glob
        else                           # default GLOB
          files = (self + '.*').R.glob #  base + extension
          files = (self + '*').R.glob if files.empty? # prefix
          [self, files]
        end
       end).flatten.compact.uniq.select(&:exist?).map{|n|n.bindEnv env}
    end

    def fixedFormat? format = nil
      return true if upstreamUI?
      return false if env[:transformable] || !format || format.match?(/\/(atom|rss|xml)/i)
      format.match? NoTransform # MIME-pattern: application/* and media/* fixed, graph + text formats transformable
    end

    def self.GET arg, lambda
      HostGET[arg] = lambda
    end
    alias_method :get, :fetch

    def GETresource
      if path.match? /\D204$/     # connectivity-check
        [204, {}, []]
      elsif handler=HostGET[host] # host handler
        handler[self]
      elsif self.CDN? && allowContent?
        fetch
      elsif gunk?
        deny
      else
        env[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs unless !path || path == '/'
        if local?
          if %w{y year m month d day h hour}.member? parts[0]              # timeseg redirect
            dateDir
          elsif path == '/mail'                                            # inbox redirect
            [302,{'Location' => '/d/*/msg*?head&sort=date&view=table'},[]]
          elsif file?                                                      # local file
            fileResponse
          elsif directory? && qs.empty? && (index = (self + 'index.html').R env).exist? && selectFormat == 'text/html'
            index.fileResponse                                             # directory-index file
          else
            env[:links][:turtle] = (path[-1] == '/' ? 'index' : name) + '.ttl' # local graph-files
            dateMeta
            nodeResponse
          end
        else
          fetch
        end
      end
    rescue OpenURI::HTTPRedirect => e
      redirect e.io.meta['location']
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

    def gunk?
      return false if env[:query]['allow'] == ServerKey
      return true if env.has_key?('HTTP_GUNK') && !AllowedHosts.has_key?(host) # upstream tag - domain-name derived
      gunkURI                                                                  # local tag - URI-regex derived
    end

    def gunkURI
      return false if env[:query]['allow'] == ServerKey
      ('/' + hostname + (env && env['REQUEST_URI'] || path || '/')).match? Gunk
    end

    def HEAD
      send(Methods['GET']).yield_self{|s,h,_| [s,h,[]] } # status-code & header
    end

    # header formatted and filtered
    def headers hdr = nil
      head = {} # header storage

      (hdr || env || {}).map{|k,v| # raw headers
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
transfer-encoding unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}

      # Cookie
      unless AllowedHosts.has_key?(host) || CookieHost.has_key?(host)
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
      end

      # Referer
      head.delete 'Referer' unless AllowedHosts.has_key? host
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

    # load node metadata/RDF to RDF::Repository
    def load options = {}
      env[:repository] ||= RDF::Repository.new # graph
      stat options                             # load node-metadata
      return self unless file?                 # directories are metadata-only
      options[:base_uri] ||= self              # base-URI
      options[:format]  ||= formatHint         # path-derived format hint
      env[:repository].load relPath, options   # load RDF
      self                                     # node
    end

    def local?; LocalAddr.member?(env['SERVER_NAME']) || ENV['SERVER_NAME'] == env['SERVER_NAME'] end

    def nodeResponse fs_base=self
      nodes = fs_base.findNodes
      if nodes.size==1 && nodes[0].ext=='ttl' && selectFormat=='text/turtle'
        nodes[0].fileResponse # nothing to transform or merge. return file
      else                    # merge and transform
        nodes.map{|node|
          options = fs_base == self ? {} : {base_uri: (join node.relFrom fs_base)}
          node.load options}
        graphResponse
      end
    end

    def notfound
      dateMeta # nearby nodes may exist, search for pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def offline?
      ENV.has_key? 'OFFLINE'
    end

    def OPTIONS
      if AllowedHosts.has_key? host
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
      elsif AllowedHosts.has_key?(host) || (ENV.has_key?('TWITCH')&&host.match?(/\.ttvnw\.net$/))
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
        puts "REQUEST HEAD:"
        HTTP.print_header head
        puts "REQUEST BODY:"
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
        if env[:query] && LocalArgs.find{|a|env[:query].has_key? a} # parsed query w/ local args in use
          q = env[:query].dup          # copy query
          LocalArgs.map{|a|q.delete a} # strip local args
          q.empty? ? '' : HTTP.qs(q)   # serialize
        elsif env['QUERY_STRING'] && !env['QUERY_STRING'].empty?    # query-string from environment
          '?' + env['QUERY_STRING']
        else                                                        # query-string from URI
          staticQuery
        end
      else
        staticQuery
      end
    end

    alias_method :qs, :querystring

    def redirect location
      if location.match? /campaign|[iu]tm_/
        l = location.R
        location = (l.host ? ('https://' + l.host) : '') + (l.path||'/') # strip query
      end
      [302, {'Location' => location}, []]
    end

    def stat options = {}
      return if basename.index('msg.') == 0 || ext=='ttl'           # hide internal graph-storage nodes
      graph = env[:repository] ||= RDF::Repository.new
      options[:base_uri] ||= self
      subject = options[:base_uri].R
      if node.directory?
        subject = subject.to_s[-1] == '/' ? subject : (subject+'/') # enforce trailing slash on container URI
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Container').R)
        node.children.map{|n|                                       # point to contained nodes TODO recursion w/ stop-recursion flag?
          directory = n.directory?
          file = n.file?
          name = n.basename.to_s
          name = directory ? (name + '/') : name.sub(GraphExt, '')
          child = subject.join name
          graph << (RDF::Statement.new subject, (W3+'ns/ldp#contains').R, child)
          graph << (RDF::Statement.new child, Title.R, name)
          if directory
            graph << (RDF::Statement.new child, Type.R, (W3+'ns/ldp#Container').R)
          elsif file
            graph << (RDF::Statement.new child, Type.R, (W3+'ns/posix/stat#File').R)
            graph << (RDF::Statement.new child, (W3+'ns/posix/stat#size').R, n.size)
          end
          if file || directory
            mtime = n.stat.mtime
            graph << (RDF::Statement.new child, Date.R, mtime.iso8601)
            graph << (RDF::Statement.new child, (W3+'ns/posix/stat#mtime').R, mtime.to_i)
          end}
      else
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/posix/stat#File').R)
      end
      graph << (RDF::Statement.new subject, Title.R, basename)
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)
      mtime = node.stat.mtime
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#mtime').R, mtime.to_i)
      graph << (RDF::Statement.new subject, Date.R, mtime.iso8601)
      self
    end

    def staticQuery
      if query && !query.empty?
        '?' + query
      else
        ''
      end
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
    def upstreamUI?; env.has_key?(:UX) || ENV.has_key?('UX') || env[:query].has_key?('UX') || env['HTTP_REFERER']&.match?(/UX=upstream/) end

    def verbose?; ENV.has_key? 'VERBOSE' end

  end
  include HTTP
end
