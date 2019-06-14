# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    Hosts = {}   # seen hosts
    HostGET = {} # lambda tables
    PathGET = {}
    OFFLINE = ENV.has_key? 'OFFLINE'
    SiteGIF = ConfDir.join('site.gif').read

    # TODO RTFM on CORS/CORB stuff
    def allowedOrigin
      if referer = env['HTTP_REFERER']
        'https://' + referer.R.host
      else
        '*'
      end
    end

    def allowPOST?; host.match? POSThost end

    def cache; ('/' + host + path).R end

    def cacheHit?; cache.file? end

    def self.call env
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? env['REQUEST_METHOD'] # allow defined methods
      env[:Response] = {}; env[:links] = {}                      # response-header storage
      path = Pathname.new(env['REQUEST_PATH'].force_encoding('UTF-8')).expand_path.to_s # evaluate path expression
      query = env[:query] = parseQs env['QUERY_STRING']          # parse query
      resource = ('//' + env['SERVER_NAME'] + path).R env        # instantiate request
      resource.send(env['REQUEST_METHOD']).do{|status,head,body| # dispatch request
        color = (if resource.env[:deny]
                 '31'
                elsif !Hosts.has_key? env['SERVER_NAME']
                  Hosts[env['SERVER_NAME']] = resource
                  '32'
                elsif env['REQUEST_METHOD'] == 'POST'
                  '32'
                elsif status == 200
                  if resource.ext == 'js' || (head['Content-Type'] && head['Content-Type'].match?(/script/))
                    '36'
                  else
                    '37'
                  end
                else
                  '30'
                 end) + ';1'
        referer = env['HTTP_REFERER']
        referrer = if referer
                     r = referer.R
                     "\e[" + color + ";7m" + (r.host || '').sub(/^www\./,'').sub(/\.com$/,'') + "\e[0m -> "
                   else
                     ''
                   end
        relocation = head['Location'] ? (" ↝ " + head['Location']) : ""
        # log request to console
        puts "\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : env['REQUEST_METHOD']) + "\e[" + color + "m "  + status.to_s + "\e[0m " + referrer + ' ' +
             "\e[" + color + ";7mhttps://" + env['SERVER_NAME'] + "\e[0m\e[" + color + "m" + env['REQUEST_PATH'] + resource.qs + "\e[0m " + relocation
        # response
        [status, head, body]}
    rescue Exception => e
      uri = 'https://' + env['SERVER_NAME'] + env['REQUEST_URI']
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts "\e[7;31m500\e[0m " + msg , trace
      [500, {'Content-Type' => 'text/html'},
       [uri.R.htmlDocument(
          {uri => {Content => [
                     {_: :h3, c: msg.hrefs, style: 'color: red'},
                     {_: :pre, c: trace.hrefs},
                     (HTML.keyval (HTML.webizeHash env), env),
                     (HTML.keyval (HTML.webizeHash e.io.meta), env if e.respond_to? :io)]}})]]
    end

    def decompress head, body
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
    end

    def deny status = 200
      env[:deny] = true
      type, content = if ext == 'js' || env[:script]
                        ['application/javascript',
                         '// TODO deliver modified scripts']
                      elsif path[-3..-1] == 'css'
                        ['text/css',
                         'body {background-color: #000; color: #fff}']
                      elsif env[:GIF]
                        ['image/gif', SiteGIF]
                      else
                        ['text/html; charset=utf-8',
                         "<html><body style='#{qs.empty? ? ('background: repeating-linear-gradient(' + (rand 360).to_s + 'deg, #000, #000 6.5em, #f00 6.5em, #f00 8em)') : 'background-color: red'}; text-align: center'><a href='#{qs.empty? ? '?allow' : path}' style='color: #fff; font-size: 28em; text-decoration: none'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end
    alias_method :drop, :deny

    def denyPOST
      head = HTTP.unmangle env
      body = env['rack.input'].read
      body = if head['Content-Encoding'].to_s.match?(/zip/)
               Zlib::Inflate.inflate(body) rescue ''
             else
               body
             end
      HTTP.print_body body, head['Content-Type'] unless host.match? /google|instagram|youtube/
      env[:deny] = true
      [202,{},[]]
    end

    def echo
      [200, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def entity env, lambda = nil
      entities = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ }
      if entities && entities.include?(env[:Response]['ETag'])
        [304, {}, []] # not modified
      else            # generate
        body = lambda ? lambda.call : self # call generator lambda
        if body.class == WebResource # static-resource reference
          (Rack::File.new nil).serving((Rack::Request.new env), body.localPath).do{|s,h,b|
            [s,h.update(env[:Response]),b]}
        else
          [env[:status] || 200, env[:Response], [body]]
        end
      end
    end

    def environment env = nil
      if env
        @r = env
        self
      else
        @r
      end
    end
    alias_method :env, :environment

    def fetch rack_API=true
      return cache.fileResponse if cacheHit?

      # request data
      @r ||= {}
      head = HTTP.unmangle env                           # strip internal headers
      head.delete 'Host'
      head['User-Agent'] = DesktopUA
      head.delete 'User-Agent' if %w{po.st t.co}.member? host
      head[:redirect] = false                            # halt internal redirects
      query = if rack_API
                q = @r[:query].dup || {}
                %w{group view sort}.map{|a| q.delete a } # strip internal qs-args
                q.empty? ? '' : HTTP.qs(q)
              else
                qs
              end
      url = if !rack_API
              'https://' + host + path + qs
            elsif suffix = ext.empty? && host.match?(/reddit.com$/) && !originUI && '.rss'
              'https://' + (env['HTTP_HOST'] || host) + path + suffix + query                  # added format-suffix
            else
              'https://' + (env['HTTP_HOST'] || host) + (env['REQUEST_URI'] || (path + query)) # extant URL
            end

      # response data
      body = nil
      file = nil
      graph = RDF::Repository.new
      meta = {}
      status = nil
      updates = nil

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' '
        begin
          open(url, head) do |response| # request
            meta = response.meta
            #HTTP.print_header head; puts "<============>"; print response.status.justArray.join(' ') + ' '; HTTP.print_header meta
            if response.status.to_s.match? /206/
              status = 206
              body = response.read
            else
              %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials ETag Set-Cookie}.map{|k| # read metadata
                @r[:Response]    ||= {}
                @r[:Response][k] ||= meta[k.downcase]}

              mime = if meta['content-type']
                       meta['content-type'].split(';')[0]
                     elsif MIMEsuffix[ext]
                       puts "WARNING missing MIME in HTTP metadata"
                       MIMEsuffix[ext]
                     else
                       puts "ERROR missing MIME in HTTP meta and URI path-extension"
                       'application/octet-stream'
                     end

              body = decompress meta, response.read                                                       # read body

              if mime.match? NonRDF
                file = cache.writeFile body
              else
                RDF::Reader.for(content_type: mime).new(body, :base_uri => self){|reader| graph << reader } # read graph
                updates.concat index graph                                                                  # index updates
              end
            end
          end
        rescue Exception => e
          case e.message
          when /304/
            status = 304 # no update
          when /401/
            status = 401 # unauthorized
          when /403/
            status = 403 # forbidden
          when /404/
            env[:status] = 404 # not found
          else
            raise
          end
        end}

      begin
        fetchURL[url]
      rescue Exception => e
        fallback = url.sub /^https/, 'http'
        case e.class.to_s
        when 'Errno::ECONNREFUSED'
          fetchURL[fallback]
        when 'Errno::ENETUNREACH'
          fetchURL[fallback]
        when 'Net::OpenTimeout'
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
            return updateLocation location
          end
        when 'RuntimeError'
          fetchURL[fallback]
        when 'SocketError'
          puts ["\e[7;31m", url, e.class, e.message, "\e[0m"].join ' '
        else
          puts ["\e[7;31m", url, e.class, e.message, "\e[0m"].join ' '
          puts e.backtrace
        end
      end

      return updates unless rack_API

      if file
        file.fileResponse
      elsif 206 == status
        [206, meta, [body]]
      elsif [304, 401, 403].member? status
        [status, meta, []]
      else
        graphResponse graph
      end
    end

    def GET
      return [204,{'Content-Length'=>[0]},[]] if path.match? /204$/
      return PathGET[path][self] if PathGET[path] # path lambda
      return HostGET[host][self] if HostGET[host] # host lambda
      local || remote
    end

    def GETthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      # response
      r = HTTParty.get url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      [s, h, [b]]
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    def local
      if localNode?
        if %w{y year m month d day h hour}.member? parts[0] # timeslice redirect
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
          [303, @r[:Response].update({'Location' => loc + parts[1..-1].join('/') + qs}), []]
        elsif file?
          fileResponse
        else
          graph = RDF::Graph.new
          nodes.map{|node|
            graph.load node.localPath, :base_uri => self}
          graphResponse graph
        end
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def localNode?; LocalAddr.member?(@r['SERVER_NAME']||host) end

    def metafile type = 'meta'
      dir + (dirname[-1] == '/' ? '' : '/') + '.' + basename + '.' + type
    end

    def no_cache; pragma && pragma == 'no-cache' end

    # filter scripts
    def noexec
      if %w{gif js}.member? ext.downcase # filtered suffix
        if ext=='gif' && qs.empty? # no querystring, allow GIF
          fetch
        else
          deny
        end
      else # fetch and inspect
        fetch.do{|status, h, b|
          if status.to_s.match? /30[1-3]/ # redirected
            [status, h, b]
          else
            if h['Content-Type'] && !h['Content-Type'].match?(/image.(bmp|gif)|script/)
              [status, h, b] # allowed MIME
            else # filtered MIME
              env[:GIF] = true if h['Content-Type']&.match? /image\/gif/
              env[:script] = true if h['Content-Type']&.match? /script/
              deny status
            end
          end}
      end
    end

    def notfound
      dateMeta # nearby page may exist, search for pointers
      [404,{'Content-Type' => 'text/html'},[htmlDocument]]
    end

    def OPTIONS
      if allowPOST?
        self.OPTIONSthru
      else
        env[:deny] = true
        [202,{},[]]
      end
    end

    def OPTIONSthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      # response
      r = HTTParty.options url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      [s, h, [b]]
    end

    def originUI
      if %w{duckduckgo.com soundcloud.com}.member? host
        true
      elsif env['HTTP_USER_AGENT'] == DesktopUA
        true
      else
        false
      end
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
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      %w{Host Query}.map{|k| headers.delete k }
      body = env['rack.input'].read

      puts "->"
      HTTP.print_header headers
      HTTP.print_body body, headers['Content-Type']

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body

      puts "<-"
      HTTP.print_header h
      HTTP.print_body decompress(h, b), h['content-type']

      [s, h, [b]]
    end

    def pragma; env['HTTP_PRAGMA'] end

    def HTTP.print_body body, mime
      puts mime
      case mime
      when /application\/json/
        json = ::JSON.parse body rescue nil
        if json
          puts ::JSON.pretty_generate json
        else
          puts body
        end
      when /application\/x-www-form-urlencoded/
        q = HTTP.parseQs body
        message = q.delete "message"
        puts q
        puts ::JSON.pretty_generate ::JSON.parse message if message
      when /text\/plain/
        json = ::JSON.parse body rescue nil
        if json
          puts ::JSON.pretty_generate json
        else
          puts body
        end
      else
        puts body
      end
    end

    def HTTP.print_header header
      header.map{|k,v|
            puts [k,v].join "\t"}
    end

    def PUT
      env[:deny] = true
      [202,{},[]]
    end

    # query-string -> Hash
    def q
      @q ||= HTTP.parseQs qs[1..-1]
    end

    # Hash -> query-string
    def HTTP.qs h
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.intersperse("&").join('')
    end

    # env or URI -> query-string
    def qs
      if @r && @r['QUERY_STRING'] && !@r['QUERY_STRING'].empty?
        '?' +  @r['QUERY_STRING']
      elsif query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    def relocation
      hash = (host + (path || '') + qs).sha2
      ('/cache/location/' + hash[0..2] + '/' + hash[3..-1] + '.u').R
    end

    def redirect
      [302, {'Location' => relocation.readFile}, []]
    end

    def relocated?
      relocation.exist?
    end

    # dispatch request for remote resource
    def remote
      if env.has_key? 'HTTP_TYPE'
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch # allow music tracks
          elsif qs == '?allow' # allow with stripped querystring
            env.delete 'QUERY_STRING'
            env['REQUEST_URI'] = env['REQUEST_PATH']
            puts "ALLOW #{uri}" # notify on console
            fetch
          else
            drop
          end
        when /noexec/
          noexec # strip JS
        when /direct/
          self.GETthru # direct to origin
        end
      else
        fetch
      end
    rescue OpenURI::HTTPRedirect => e
      updateLocation e.io.meta['location']
    end

    # ALL_CAPS (CGI/env-var) key-names to standard HTTP capitalization
    # ..is there any way to have Rack give us the names straight out of the HTTP parser?
    def self.unmangle env
      head = {}
      env.map{|k,v|
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split('_').map{|k| # eat prefix and process tokens
          if %w{cl id spf utc xsrf}.member? k # acronyms
            k = k.upcase
          else
            k[0] = k[0].upcase # capitalize word
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored
        # strip internal headers
        head[key] = v.to_s unless %w{links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}
      head
    end

    def updateLocation location
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|twitter|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

  end
  include HTTP
end
