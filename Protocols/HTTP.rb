# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs
    AllowedHosts = {}
    BaseMeta = %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag Set-Cookie)
    HostGET = {}
    HostPOST = {}
    Hosts = {}
    LocalArgs = %w(allow view sort ui)
    Methods = {'GET' => :GETresource, 'HEAD' => :HEAD, 'OPTIONS' => :OPTIONS, 'POST' => :POSTresource}
    NoTransform = /^(application|audio|font|image|text\/(css|(x-)?javascript|proto)|video)/
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join)[0..7]

    def self.Allow host
      AllowedHosts[host] = true
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
      return [405,{},[]] unless m=Methods[env['REQUEST_METHOD']] # find method handler
      path = Pathname.new(env['REQUEST_PATH']).expand_path.to_s  # evaluate path expression
      path+='/' if env['REQUEST_PATH'][-1]=='/' && path[-1]!='/' # preserve trailing slash
      resource = ('//' + env['SERVER_NAME'] + path).R env.merge( # instantiate request w/ blank response fields
       {resp:{}, links:{}, query: parseQs(env['QUERY_STRING'])}) # parse query
      resource.send(m).yield_self{|status, head, body|           # dispatch request
        ext = resource.ext.downcase
        mime = head['Content-Type'] || ''
        parts = resource.parts
        verbose = resource.verbose?
        if resource.env[:deny]                                   # log request
          print "\n🛑\e[31;1m" + resource.host + "\e[7m" + resource.path + "\e[0m "
          resource.env[:query]&.map{|k,v|
            print "\n\e[7m#{k}\e[0m\t#{v}"} if verbose           # blocked
        elsif [301, 302, 303].member? status
          print '➡️'; print head['Location'] if verbose           # redirected
        elsif status == 304
          print '✅'                                             # up-to-date
        elsif ext == 'css'
          print '🎨'                                             # stylesheet
        elsif ext == 'js' || mime.match?(/script/)
          print "\n📜\e[36m https://" + resource.host + "\e[1m" + resource.path + "\e[0m "
        elsif %w(gif jpeg jpg).member?(ext)
          print '🖼️'                                              # picture
        elsif %w(png svg webp).member?(ext) || mime.match?(/^image/)
          print '🖌'                                              # image
        elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
          print '🔉'                                             # audio
        elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
          print '🎬'                                             # video
        elsif ext == 'ttl' || mime == 'text/turtle; charset=utf-8'
          print '🐢'                                             # turtle
        elsif parts.member?('gql')||parts.member?('graphql')||parts.member?('query')||parts.member?('search')
          print '🔍'
        else
          color = (if env['REQUEST_METHOD'] == 'POST'
                    '32'                                         # green -> POST
                  elsif status == 200
                    '37'                                         # white -> basic
                  else
                    '30'                                         # gray -> other
                   end) + ';1'
          print "\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : env['REQUEST_METHOD']) +
                "\e[" + color + "m"  + (status == 200 ? '' : status.to_s) + (env['HTTP_REFERER'] ? (' ' + (env['HTTP_REFERER'].R.host || '').sub(/^www\./,'').sub(/\.com$/,'') + "\e[0m→") : ' ') +
                "\e[" + color + ";7m https://" + env['SERVER_NAME'] + "\e[0m\e[" + color + "m" + env['REQUEST_PATH'] + (env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || '') + "\e[0m "
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

    def CDN?; host.match? /\.(amazonaws|cloud(f(lare|ront)|inary))\.(com|net)$/ end

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

    def desktop; env['HTTP_USER_AGENT'] = DesktopUA; self end
    def desktopUI?
      env['HTTP_USER_AGENT']&.match?(/Mozilla\/5.0 \((Windows NT 10.0; Win64; x64|X11; Linux x86_64)\) AppleWebKit\/\d+.\d+ \(KHTML, like Gecko\) Chrome\/\d+.\d+.\d+.\d+ Safari\/\d+.\d+/) ||
      env['HTTP_USER_AGENT']&.match?(/Mozilla\/5.0 \(X11; Linux x86_64; rv:\d+.\d+\) Gecko\/\d+ Firefox\/\d+.\d+/)
    end
    alias_method :desktopUA?, :desktopUI?

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
      if StaticFormats.member? ext.downcase # immutable cache types
        return [304,{},[]] if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has resource
        return cache.fileResponse if cache.node.file?                                                    # server has resource
      end
      return graphResponse if offline?      # can't fetch if offline, return cached graph

      if !Hosts.has_key? host
        Hosts[host] = true
        print "\n➕\e[32;1mhttps://" + hostname + "\e[2m" + (path || '/') + "\e[0m "
      end

      # locators
      u = '//'+hostname+path+(options[:suffix]||'')+(options[:query] ? (HTTP.qs options[:query]) : qs) # base, sans scheme
      primary  = ((options[:scheme] || 'https').to_s + ':' + u).R env    # primary locator
      fallback = ((options[:scheme] ? 'https' : 'http') + ':' + u).R env # fallback locator

      primary.fetchHTTP options # fetch
    rescue Exception => e       # fetch failed
      case e.class.to_s
      when 'OpenURI::HTTPRedirect'   # redirected
        if fallback == e.io.meta['location']
          fallback.fetchHTTP options # follow to fallback transit
        elsif options[:intermedate]                       # non-HTTP caller
          puts "RELOC #{uri} -> #{e.io.meta['location']}" # alert caller of new location
          e.io.meta['location'].R(env).fetchHTTP options  # follow redirect
        else                                              # alert HTTP caller of new location
          redirect e.io.meta['location']                  # client can follow at discretion
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
        h = response.meta                                                 # upstream metadata
        if response.status.to_s.match? /206/                              # partial body
          [206, h, [response.read]]                                       # return part
        else print '🌍🌎🌏🌐'[rand 4]; print uri if verbose?              # complete body
          body = HTTP.decompress h, response.read                         # decode body
          cache.write body if StaticFormats.member? ext.downcase          # store body
          format = h['content-type'].split(/;/)[0] if h['content-type']   # format
          format ||= (xt=ext.to_sym                                       # extension -> format
            RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])
          reader = RDF::Reader.for content_type: format                   # find RDF reader
          reader.new(body, {base_uri: self, noRDF: options[:noRDF]}){|_|  # instantiate RDF reader
            (env[:repository] ||= RDF::Repository.new) << _ } if reader   # read RDF
          options[:intermediate] ? (return self) : index                  # return if load-only
          BaseMeta.map{|k|env[:resp][k]||=h[k.downcase] if h[k.downcase]} # downstream metadata
          env[:resp]['Content-Length'] = body.bytesize.to_s               # content-length
          (fixedFormat? format) ? [200,env[:resp],[body]] : graphResponse # HTTP response
        end
      end
    rescue Exception => e
      case e.message
      when /300/ # multiple choices
        [300, e.io.meta, [e.io.read]]
      when /304/ # not modified
        print '✅ '+uri; [304, {}, []]
      when /401/ # unauthorized
        print '🚫 '+uri; notfound
      when /403/ # forbidden
        print '🚫 '+uri; notfound
      when /404/ # not found
        print '❓ '+uri+' '
        if options[:intermediate]
          self
        else # cache may exist, bypass immediate 404
          graphResponse
        end
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

    def fixedFormat? format = nil
      return true if desktopUI? || mobileUI? || path.match?(/embed/) || host.match?(/embed|video/)
      return false if !format || (format.match? /\/(atom|rss|xml)/i) # allow feed rewriting
      format.match? NoTransform # MIME-regex. application/media fixed, graph-data + text transformable
    end

    def self.GET arg, lambda
      HostGET[arg] = lambda
    end

    def GETresource
      if path.match? /\D204$/     # connectivity-check
        env[:deny] = true
        [204, {}, []]
      elsif handler=HostGET[host] # host handler
        handler[self]
      elsif self.CDN? && %w(mp3 jpg png).member?(ext.downcase) && !gunkURI
        fetch
      elsif gunk? && ServerKey != env[:query]['allow']
        deny
      else
        env[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs unless !path || path == '/'
        local? ? local : fetch
      end
    rescue OpenURI::HTTPRedirect => e
      redirect e.io.meta['location']
    end

    def graphResponse
      cache.nodeStat base_uri: self unless local? || !cache.exist?
      return notfound if !env.has_key?(:repository) || env[:repository].empty?

      format = selectFormat
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?

      entity ->{
        case format
        when /^text\/html/
          htmlDocument treeFromGraph
        when /^application\/atom+xml/
          feedDocument treeFromGraph
        else
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true
        end}
    end

    def gunk?; gunkHost || gunkURI end # match by host or URI regular-expression
    def gunkHost; !AllowedHosts.has_key?(host) && env.has_key?('HTTP_GHOST') end
    def gunkURI; ('/' + env['SERVER_NAME'] + env['REQUEST_URI']).match? Gunk end

    def HEAD
      send(Methods['GET']).yield_self{|s,h,_|
        [s,h,[]]} # return status & header
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
      unless AllowedHosts.has_key? host
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
      head['User-Agent'] = DesktopUA if desktopUA?
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st'
      head.delete 'User-Agent' if host == 't.co'

      head # output header
    end

    def local
      if %w{y year m month d day h hour}.member? parts[0] # time-based redirect
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
      elsif path == '/mail' # inbox redirect
        [302, {'Location' => '/d/*/msg*?head&sort=date&view=table'}, []]
      elsif node.file?
        fileResponse
      elsif node.directory? && qs.empty? && (index = (self+'index.html').R.env env).exist? && selectFormat == 'text/html'
        index.fileResponse
      else
        localGraph
      end
    end

    # WebResource -> HTTP Response
    def localGraph
      rdf, nonRDF = nodes.partition &:isRDF?
      if rdf.size==1 && nonRDF.size==0 && selectFormat == 'text/turtle'
        rdf[0].fileResponse # response on file
      else
        nonRDF.map &:load # load nonRDF
       #index             # index RDF-ized nodes
        rdf.map &:load    # load RDF
        dateMeta
        graphResponse     # response
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(env['SERVER_NAME']) || ENV['SERVER_NAME'] == env['SERVER_NAME'] end

    def mobile; env['HTTP_USER_AGENT'] = MobileUA; self end
    def mobileUI?; env['HTTP_USER_AGENT'] == MobileUA end
    alias_method :mobileUA?, :mobileUI?

    def nodes # URI -> file(s)
      (if node.directory?
       if env[:query].has_key?('f') && path != '/'  # FIND
          find env[:query]['f'] unless env[:query]['f'].empty? # exact
       elsif env[:query].has_key?('find') && path != '/' # easymode find
          find '*' + env[:query]['find'] + '*' unless env[:query]['find'].empty?
       elsif env[:query].has_key?('q') && path!='/' # GREP
         env[:grep] = true
         grep
       else
         [self,node.children.map{|c|('/'+c.to_s).R env}] # LS
       end
      else                             # GLOB
        if uri.match /[\*\{\[]/        # parametric glob
          env[:grep] = true if env[:query].has_key?('q')
          glob
        else                           # basic glob:
          files = (self + '.*').R.glob #  base + extension
          files = (self + '*').R.glob if files.empty? # prefix
          [self, files]
        end
       end).flatten.compact.uniq.select(&:exist?).map{|n|n.env env}
    end

    def notfound
      dateMeta # nearby nodes may exist, search for pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def offline
      env[:query]['offline'] = true
      self
    end

    def offline?
      ENV.has_key?('OFFLINE') || env[:query].has_key?('offline')
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
    def HTTP.parseQs qs
      if qs
        h = {}
        qs.split(/&/).map{|e|
          k, v = e.split(/=/,2).map{|x|CGI.unescape x}
          h[(k||'').downcase] = v}
        h
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
      print '📝'

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
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.join("&")
    end

    # external query-string
    def qs
      if env
        if env[:query] && LocalArgs.find{|a|env[:query].has_key? a} # dynamic w/ local args in use
          q = env[:query].dup          # copy query
          LocalArgs.map{|a|q.delete a} # strip local args
          q.empty? ? '' : HTTP.qs(q)   # serialize
        elsif env['QUERY_STRING'] && !env['QUERY_STRING'].empty?    # dynamic
          '?' + env['QUERY_STRING']
        else                                                        # static
          staticQuery
        end
      else
        staticQuery
      end
    end

    def redirect location
      if location.match? /campaign|[iu]tm_/
        l = location.R
        location = (l.host ? ('https://' + l.host) : '') + l.path # strip query
      end
      [302, {'Location' => location}, []]
    end

    def staticQuery
      if query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    def selectFormat default='text/html'
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

    def verbose?; ENV.has_key? 'VERBOSE' end

  end
  include HTTP
end
