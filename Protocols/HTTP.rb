# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs
    HostGET = {}
    Hosts = {}
    LocalArgs = %w(allow view sort ui)
    Methods = %w(GET HEAD OPTIONS POST)
    OffLine = ENV.has_key? 'OFFLINE'
    PathGET = {}
    PreservedFormat = /^(application\/(json|protobuf|vnd|x-)|audio|font|text\/xml|video)/
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Subdomain = {}

    def allowed
      env[:query]['allow'] == ServerKey
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

    def allowCookies?
      ENV.has_key?('COOKIES') || hostname.match?(CookieHost)
    end

    def allowHost
      return deny if gunkURI
      fetch
    end

    def allowPOST?
      host.match?(POSThost) ||
      path.match?(POSTpath)
    end

    # cache reference
    def cache format=nil
      want_suffix = ext.empty?
      hostPart = CacheDir + (host || 'localhost')
      pathPart = if !path || path[-1] == '/'
                   want_suffix = true
                   '/index'
                 elsif path.size > 127
                   want_suffix = true
                   hash = Digest::SHA2.hexdigest path
                   '/' + hash[0..1] + '/' + hash[2..-1]
                 else
                   path
                 end
      qsPart = if qs.empty?
                 ''
               else
                 want_suffix = true
                 '.' + Digest::SHA2.hexdigest(qs)
               end
      suffix = if want_suffix
                 if !ext || ext.empty? || ext.size > 11
                   if format
                     if xt = Extensions[RDF::Format.content_types[format]]
                       '.' + xt.to_s # suffix found in format-map
                     else
                       '' # content-type unmapped
                     end
                   else
                     '' # content-type unknown
                   end
                 else
                   '.' + ext # restore known suffix
                 end
               else
                 '' # suffix already exists
               end
      (hostPart + pathPart + qsPart + suffix).R env
    end

    def cached
      return false if env && env['HTTP_PRAGMA'] == 'no-cache'
      cache.cached_static
    end

    def cached_static
      %w(css gif jpg js png mp3 mp4 opus webm webp).member?(ext.downcase) && file? && self
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']    # permit HTTP methods
      env['HTTP_ACCEPT'] ||= '*/*'                                       # Accept default
      env[:resp] = {}; env[:links] = {}                                  # response-header storage
      env[:query] = parseQs env['QUERY_STRING']                          # parse query
      path = Pathname.new(env['REQUEST_PATH']).expand_path.to_s          # evaluate path-expression
      path += '/' if env['REQUEST_PATH'][-1] == '/' && path[-1] != '/'   # preserve trailing-slash
      resource = ('//' + env['SERVER_NAME'] + path).R env                # instantiate request
      resource.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # dispatch request
        color = (if resource.env[:deny]                                  # log request
                  '31'                                                    # red -> denied
                elsif !Hosts.has_key? env['SERVER_NAME']
                  Hosts[env['SERVER_NAME']] = resource
                  '32'                                                    # green -> new host
                elsif env['REQUEST_METHOD'] == 'POST'
                  '32'                                                    # green -> POST
                elsif status == 200
                  if resource.ext=='js' || (head['Content-Type'] && head['Content-Type'].match?(/script/))
                    '36'                                                  # lightblue -> executable
                  else
                    '37'                                                  # white -> basic response
                  end
                else
                  '30'                                                    # gray -> cache-hit, 304 response
                end) + ';1'

        puts "\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : env['REQUEST_METHOD']) +
             "\e[" + color + "m "  + status.to_s +
             "\e[0m" + (env['HTTP_REFERER'] ? (" \e[" + color + ";7m" + (env['HTTP_REFERER'].R.host || '').sub(/^www\./,'').sub(/\.com$/,'') + "\e[0m -> ") : ' ') +
             "\e[" + color + ";7mhttps://" + env['SERVER_NAME'] +
             "\e[0m\e[" + color + "m" + env['REQUEST_PATH'] + (env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || '') +
             "\e[0m " + (head['Location'] ? (" ↝ " + head['Location']) : '') + ' ' +
             (head['Content-Type'] == 'text/turtle; charset=utf-8' ? '🐢' : (head['Content-Type']||''))

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
      case head['content-encoding'].to_s
      when /^br(otli)?$/i
        Brotli.inflate body
      when /gzip/i
        (Zlib::GzipReader.new StringIO.new body).read
      when /flate|zip/i
        Zlib::Inflate.inflate body
      else
        body
      end
    rescue Zlib::DataError
      ''
    end

    def deny status=200, type=nil
      return [301,{'Location'=>env['REQUEST_PATH']},[]] if !env[:query].keys.grep(/campaign|[iu]tm_/).empty?
      env[:deny] = true
      type, content = if ext == 'js' || type == :script
                        source = ConfDir.join 'alternatives/' + host + path
                        ['application/javascript',
                         source.exist? ? source.read : '//']
                      elsif path[-3..-1] == 'css'
                        ['text/css',"body {background: repeating-linear-gradient(#{rand 360}deg, #000, #000 6.5em, #fff 6.5em, #fff 8em)\ndiv, p {background-color: #000; color: #fff}"]
                      elsif ext == 'woff' || ext == 'woff2'
                        ['font/woff2', SiteFont]
                      elsif %w(gif png).member?(ext) || type == :image
                        ['image/gif', SiteGIF]
                      elsif ext == 'json' || type == :json
                        ['application/json','{}']
                      else
                        q = env[:query].dup
                        q['allow'] = ServerKey
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{HTTP.qs q}' style='color: #fff; font-size: 22em; text-decoration: none'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      HTTP.print_body headers, env['rack.input'].read #if verbose?
      env[:deny] = true
      [202, {'Access-Control-Allow-Credentials' => 'true',
            'Access-Control-Allow-Origin' => allowedOrigin},
       []]
    end

    def desktop; env['HTTP_USER_AGENT'] = DesktopUA[0]; self end

    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/ # entities
      if entities && entities.include?(env[:resp]['ETag']) # client has entity
        [304, {}, []]                            # unmodified
      else
        body = generator ? generator.call : self # generate
        if body.class == WebResource             # resource reference?
          Rack::File.new(nil).serving(Rack::Request.new(env), body.relPath).yield_self{|s,h,b|
          if s == 304
            [s, {}, []]                          # unmodified
          else                                   # Rack handler for reference
            h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type'] == 'application/javascript'
            env[:resp]['Content-Length'] = body.node.size.to_s
            [s, h.update(env[:resp]), b]         # file
          end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [env[:status]||200,env[:resp],[body]]  # generated entity
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

    def fetch options = {}
      if file = !options[:no_response] && cached; return file.fileResponse end
      @env ||= {resp: {}}                      # response metadata
      env[:repository] ||= RDF::Repository.new # RDF storage (in-memory)
      head = headers                           # cleaned request metadata
      head[:redirect] = false                  # halt on redirect
      u = '//' + hostname + path + (env[:suffix]||'') + qs        # base locator
      url      = (options[:scheme] || 'https').to_s    + ':' + u  # primary locator
      fallback = (options[:scheme] ? 'https' : 'http') + ':' + u  # fallback locator
      options[:content_type]='application/atom+xml' if FeedURL[u] # fix MIME on feed URLs
      upstream_metas = %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials
                          Content-Type Content-Length ETag}
      upstream_metas.push 'Set-Cookie' if allowCookies?
      code = nil   # response status
      body = nil   # response body
      format = nil # response format
      file = nil   # response fileref

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' '
        if verbose?
          print url, "\nREQUEST raw-meta:\n"
          HTTP.print_header head
          puts "REQUEST cleaned-meta:"
        end
        begin
          open(url, head) do |response|
            base = url.R env
            env[:scheme] = base.scheme
            code = response.status.to_s.match(/\d{3}/)[0]
            meta = response.meta
            HTTP.print_header meta if verbose?
            if code == 206
              body = response.read                                         # partial body
              upstream_metas.push 'Content-Encoding'                       # encoding preserved
            else                                                           # complete body
              body = HTTP.decompress meta, response.read                   # decode body
              format ||= options[:content_type]                                     # local format preference
              format ||= meta['content-type'].split(/;/)[0] if meta['content-type'] # Content-Type metadata
              format ||= (xt = ext.to_sym                                           # path-ext format hint
                          RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])
              format ||= body.bytesize < 2048 ? 'text/plain' : 'application/octet-stream' # unspecified format
              file = cache(format).write body if !format.match? RDFformats # cache non-RDF
              if reader = RDF::Reader.for(content_type: format)            # RDF reader
                reader_options = {base_uri: base, no_embeds: options[:no_embeds]}
                reader.new(body, reader_options){|_| env[:repository] << _ } # read RDF
                index unless options[:no_index]                            # cache RDF
              end
            end
            upstream_metas.map{|k| # origin metadata
              env[:resp][k] ||= meta[k.downcase] if meta[k.downcase]}
            HTTP.print_header env[:resp] if verbose?
          end
        rescue Exception => e
          if verbose? && !e.message.match?(/304/)
            puts e.message
            if e.respond_to? :io
              puts e.io.status.join ' '
              HTTP.print_header e.io.meta
            end
          end
          case e.message # response-types handled in normal control-flow
          when /304/ # no updates
            code = 304
          when /401/ # unauthorized
            code = 401
          when /403/ # forbidden
            code = 403
          when /404/ # not found
            code = 404
          when /999/
            code = 999
            body = HTTP.decompress e.io.meta, e.io.read
            @upstreamUI = true
          else
            raise # exceptional code
          end
        end}

      begin
        fetchURL[url]       #   try (HTTPS default)
      rescue Exception => e # retry (HTTP)
        if e.respond_to?(:io) && verbose?
          puts e.io.status.join ' '
          HTTP.print_header e.io.meta
        end
        case e.class.to_s
        when 'Errno::ECONNREFUSED'
          fetchURL[fallback]
        when 'Errno::ECONNRESET'
          fetchURL[fallback]
        when 'Errno::ENETUNREACH'
          fetchURL[fallback]
        when 'Net::OpenTimeout'
          fetchURL[fallback]
        when 'Net::ReadTimeout'
          fetchURL[fallback]
        when 'OpenSSL::SSL::SSLError'
          fetchURL[fallback]
        when 'OpenURI::HTTPError'
          fetchURL[fallback]
        when 'OpenURI::HTTPRedirect'
          location = e.io.meta['location']
          if location == fallback
            fetchURL[fallback]
          else
            return [302, {'Location' => location}, []] unless options[:no_response]
            puts "REDIRECT #{url} → \e[32;7m" + location + "\e[0m"
            fetchURL[location]
          end
        when 'RuntimeError'
          fetchURL[fallback]
        when 'SocketError'
          fetchURL[fallback]
        else
          raise
        end
      end unless OffLine

      return if options[:no_response]
      if code == 304                                              # no data
        [304, {}, []]
      elsif file                                                  # file data
        file.fileResponse
      elsif code == 206                                           # partial upstream data
        [206, env[:resp], [body]]
      elsif body && (upstreamUI? || format&.match?(PreservedFormat)) # upstream data
        [200, env[:resp].merge({'Content-Length' => body.bytesize}), [body]]
      else                                                        # graph data
        if env[:repository].empty? && !local? && env['REQUEST_PATH'][-1]=='/' # unlistable remote
          index = (CacheDir + hostname + path).R(env)                         # local container
          index.children.map{|e|e.env(env).nodeStat base_uri: (env[:scheme] || 'https') + '://' + e.relPath} if index.node.directory? # local list
        end
        graphResponse
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def GET
      if handler = PathGET['/' + parts[0].to_s] # child paths
        handler[self]
      elsif handler = PathGET[path]             # exact path
        handler[self]
      elsif local?                              # local host
        local
      elsif path.match? /[^\/]204$/             # connectivity check
        [204, {}, []]
      elsif handler = HostGET[host]             # specific host
        handler[self]
      elsif handler = Subdomain[host.split('.')[1..-1].join('.')]
        handler[self]                           # subdomains of host
      else
        return deny if (gunkHost || gunkURI) && !allowed
        return noexec if env['SERVER_NAME'].match? CDNhost
        fetch
      end
    rescue OpenURI::HTTPRedirect => e
      [302,{'Location' => e.io.meta['location']},[]]
    end

    def gunkHost
      env.has_key? 'HTTP_GUNK'
    end

    def gunkURI
      ('//'+env['SERVER_NAME']+env['REQUEST_URI']).match?(GunkURI) && !host.match?(MediaHost)
    end

    def self.getFeeds
      FeedURL.values.shuffle.map{|feed|
        begin
          options = {
            content_type: 'application/atom+xml',
            no_response: true,
          }
          options[:scheme] = :http if feed.scheme == 'http'
          feed.fetch options
          nil
        rescue Exception => e
          puts 'https:' + feed.uri, e.class, e.message, e.backtrace
        end}
    end

    # Graph -> HTTP Response
    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
      format = selectFormat
      dateMeta if local?
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument treeFromGraph # HTML
        when /^application\/atom+xml/
          renderFeed treeFromGraph   # Atom/RSS-feed
        else                         # RDF
          base = ((env[:scheme] || 'https') + '://' + env['SERVER_NAME']).R.join env['REQUEST_PATH']
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => base, :standard_prefixes => true
        end}
    end

    def HEAD
       c,h,b = self.GET
      [c,h,[]]
    end

    # header keys from lower-case and CGI_ALL_CAPS to canonical formatting
    def headers hdr = nil
      head = {}

      # read raw headers
      (hdr || env).map{|k,v| # each key
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|k| # eat HTTP prefix from Rack
          if %w{cl dfe id spf utc xsrf}.member? k
            k = k.upcase       # acronymize
          else
            k[0] = k[0].upcase # capitalize token
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored

        # set output field, strip local headers
        head[key] = v.to_s unless %w{
connection
gunk
host
links
path-info
query query-modified query-string
rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version
remote-addr repository request-method request-path request-uri resp
script-name server-name server-port server-protocol server-software
unicorn.socket upgrade-insecure-requests
version via
x-forwarded-for}.member?(key.downcase)
      }

      head.delete 'Transfer-Encoding'

      # Cookie
      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
      end

      # Referer
      head['Referer'] = 'http://drudgereport.com/' if env['SERVER_NAME']&.match? /wsj\.com/
      head['Referer'] = head['Referer'].sub(/\?ui=upstream$/,'') if head['Referer'] && head['Referer'].match?(/\?ui=upstream$/) # strip local QS TODO remove all local vars

      # User-Agent
      head['User-Agent'] = DesktopUA[0] unless host && (host.match? UAhost)
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st' # redirect via HTTP header rather than Javascript
      head.delete 'User-Agent' if host == 't.co'            # redirect via HTTP header rather than Javascript

      head
    end

    def hostname
      env['SERVER_NAME'] || host || 'localhost'
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
      elsif file? # local file
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
        nonRDF.map &:load # load  non-RDF
        index             # index non-RDF
        rdf.map &:load    # load  RDF
        graphResponse     # response
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(env['SERVER_NAME']||host) end

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
         [self, children]              # LS
       end
      else                             # GLOB
        if uri.match /[\*\{\[]/        #  parametric glob
          env[:grep] = true if env[:query].has_key?('q')
          glob
        else                           #  basic glob:
          files = (self + '.*').R.glob #   base + extension
          files = (self + '*').R.glob if files.empty? # prefix
          [self, files]
        end
       end).flatten.compact.uniq.select(&:exist?).map{|n|n.env env}
    end

    def noexec
      return deny if %w(gif js).member?(ext.downcase) || env['REQUEST_URI'].match?(/\.png\?/)
      fetch.yield_self{|status, head, body|
        if status.to_s.match? /30[1-3]/ # redirected
          [status, head, body]
        elsif head['Content-Type'] && !head['Content-Type'].match?(/application|image.(bmp|gif)|script/)
          [status, head, body] # allowed content
        else                   # filtered content
          type = :image if head['Content-Type']&.match? /image\//
          type = :script if head['Content-Type']&.match? /script/
          type = :json if head['Content-Type']&.match? /json/
          deny status, type
        end}
    end

    def notfound
      dateMeta # nearby nodes may exist, search for pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def OPTIONS
      if allowPOST?
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

    def POST; allowPOST? ? sitePOST : denyPOST end

    def POSTthru
      # origin request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read

      verbose if uri.match? /g(raph)?ql/
      if verbose?
        puts "\nREQUEST raw-meta:"
        HTTP.print_header env
        puts "REQUEST clean-meta:"
        HTTP.print_header head
        puts "REQUEST BODY:"
        HTTP.print_body head, body
      end

      # origin response
      r = HTTParty.post url, :headers => head, :body => body
      code = r.code
      head = r.headers
      body = r.body
      head['content-length'] ||= body.bytesize.to_s if body
      head.delete 'transfer-encoding'

      if verbose?
        puts "\nRESPONSE clean meta:"
        HTTP.print_header head
        if body
          puts "RESPONSE body:"
          HTTP.print_body head, (HTTP.decompress head, body)
        end
      end
      print '📝'

      [code, head, [body]]
    end

    def HTTP.print_body head, body
      body = case head['Content-Type']
             when 'application/json'
               json = ::JSON.parse body rescue {}
               puts json['query'] if json['query']
               ::JSON.pretty_generate json
             else
               body
             end
      puts body
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

    # serialize external querystring
    def qs
      if env
        if env[:query_modified]
          HTTP.qs env[:query]
        elsif env[:query] && LocalArgs.find{|a| env[:query].has_key? a } # local query args found
          q = env[:query].dup          # copy query
          LocalArgs.map{|a|q.delete a} # strip local args
          q.empty? ? '' : HTTP.qs(q)
        elsif env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
          '?' + env['QUERY_STRING']
        else
          staticQuery
        end
      else
        staticQuery
      end
    end

    def staticQuery
      if query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    def selectFormat default='text/html'
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

    def subscribe;     subscriptionFile.touch end
    def subscribed?;   subscriptionFile.exist? end
    def subscriptions; subscriptionFile('*').R.glob.map(&:dir).map &:basename end
    def subs; puts     subscriptions.sort.join ' ' end

    PathGET['/subscribe'] = -> r {
      url = (r.env[:query]['u'] || '/').R
      url.subscribe
      [302, {'Location' => url.to_s}, []]}

    PathGET['/unsubscribe']  = -> r {
      url = (r.env[:query]['u'] || '/').R
      url.unsubscribe
      [302, {'Location' => url.to_s}, []]}

    def unsubscribe; subscriptionFile.exist? && subscriptionFile.node.delete end

    def upstreamUI?
      @upstreamUI ||= !local? && ((DesktopUA.member? env['HTTP_USER_AGENT']) ||
                                  (env['SERVER_NAME'].match?  UIhost) ||
                                  (env['REQUEST_PATH'].match? UIpath) ||
                                  env[:query]['ui'] == 'upstream' ||
                                  ENV.has_key?('DESKTOP'))
    end

    def verbose
      env[:verbose] = true
    end

    def verbose?
      (ENV.has_key? 'VERBOSE') || # process environment
      (env.has_key? :verbose)     # request environment
    end

  end
  include HTTP
end
