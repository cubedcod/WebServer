# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    Hosts = {}
    OFFLINE = ENV.has_key? 'OFFLINE'

    def allowPOST?
      (host.match? POSThost) ||
      (path.match? POSTpath)
    end

    def cacheFile
      pathname = path || ''
      pathname = pathname[-1] == '/' ? pathname[0..-2] : pathname # strip trailing slash
      keep_ext = %w{aac atom css html jpeg jpg js m3u8 map mp3 mp4 ogg opus pdf png rdf svg ttf ttl vtt webm webp woff woff2}.member?(ext.downcase) && !host&.match?(/openload|\.wiki/)
      ((host ? ('/' + host) : '') + (if qs && !qs.empty? # hashed query
                                     [pathname, qs.sha2, keep_ext ? ext : 'cache'].join '.'
                                    else
                                      keep_ext ? pathname : (pathname + '.cache')
                                     end)).R env
    end

    def self.call env
      method = env['REQUEST_METHOD']                        # lookup request-method
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? method # allow defined methods
      query = env[:query] = parseQs env['QUERY_STRING']     # parse query
      host = query['host'] || env['HTTP_HOST']|| 'localhost' # hostname
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse consecutive path-separator chars
      path  = Pathname.new(rawpath).expand_path.to_s        # evaluate path expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/'  # preserve trailing-slash
      resource = ('//' + host + path).R env                 # bind request environment and resource identifier
      env[:Response] = {}; env[:links] = {}                 # response-header storage
      resource.send(method).do{|status,head,body|           # dispatch request
        color = (if resource.env[:deny]
                 '31'
                elsif !Hosts.has_key? host # record first visit
                  Hosts[host] = resource
                  '32'
                elsif method=='POST'
                  '32'
                elsif status==200
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
        puts "\e[7m" + (method == 'GET' ? '' : method) + "\e[" + color + "m "  + status.to_s + "\e[0m " + referrer + ' ' +
             "\e[" + color + ";7mhttps://" + host + "\e[0m\e[" + color + "m" + path + resource.qs + "\e[0m " + relocation
        # response
        [status, head, body]}
    rescue Exception => e
      msg = [resource.uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      [500, {'Content-Type' => 'text/html'},
       [resource.htmlDocument(
          {resource.uri => {Content => [
                              {_: :h3, c: msg.hrefs, style: 'color: red'},
                              {_: :pre, c: trace.hrefs},
                              (HTML.table (HTML.webizeHash env), env),
                              (HTML.table (HTML.webizeHash e.io.meta), env if e.respond_to? :io)]}})]]
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

    def deny
      env[:deny] = true
      js = ext == 'js'
      [200, {'Content-Type' => js ? 'application/javascript' : 'text/html; charset=utf-8'},
       js ? ["// TODO deliver modified origin-scripts"] : ["<html><body style='background-color: red; text-align: center'><a href='#{qs.empty? ? '?allow' : path}' style='color: #fff; font-size: 28em; text-decoration: none'>⌘</a></body></html>"]]
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
      etags = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ }
      if etags && (etags.include? env[:Response]['ETag'])
        [304, {}, []] # client has entity
      else
        body = lambda ? lambda.call : self # generate
        if body.class == WebResource # body as resource reference
          # use Rack file handling
          (Rack::File.new nil).serving((Rack::Request.new env),body.localPath).do{|s,h,b|
            [s,h.update(env[:Response]),b]}
        else
          [(env[:Status]||200), env[:Response], [body]]
        end
      end
    end

    def environment env = nil
      if env
        @r = env
        self
      else
        @r || {}
      end
    end
    alias_method :env, :environment

    def fetch
      # environment
      head = HTTP.unmangle env
      head.delete 'Host'
      head['User-Agent'] = DesktopUA
      head.delete 'User-Agent' if %w{po.st t.co}.member? host

      # relocation handling
      if @r
        if relocated?
          location = join(relocation.readFile).R
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false
        end
      end

      # resource pointers and metadata
      suffix = ext.empty? && host.match?(/reddit.com$/) && !originUI && '.rss'
      url = 'https://' + host + (path || '') + (suffix || '') + qs
      cache = cacheFile
      partial_response = nil
      cacheMeta = cache.metafile
      head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
      response_meta = {}
      updates = []

      # fetcher lambda
      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3], ' '#, url, ' '
        begin
          open(url, head) do |response| # request
            if response.status.to_s.match?(/206/) # partial response
              response_meta = response.meta
              partial_response = response.read
            else # response
              %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k| @r[:Response][k] ||= response.meta[k.downcase] } if @r
              body = decompress response.meta, response.read
              unless cache.e && cache.readFile == body # unchanged
                # update cache
                cache.writeFile body
                mime = if response.meta['content-type'] # explicit MIME
                         response.meta['content-type'].split(';')[0]
                       elsif MIMEsuffix[cache.ext]      # file extension
                         MIMEsuffix[cache.ext]
                       else                             # sniff
                         cache.mimeSniff
                       end
                # updata metadata on cache file  TODO survey POSIX eattr support
                cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache'

                # index updates
                updates.concat(case mime
                               when /^(application|text)\/(atom|rss|xml)/
                                 ('file:' + cache.localPath).R.indexRDF(:format => :feed, :base_uri => uri)
                               when /^text\/html/
                                 IndexHTML[@r ? @r['SERVER_NAME'] : host].do{|indexer| indexer[cache] } || []
                               else
                                 []
                               end || [])
              end
            end
          end
        rescue Exception => e
          raise unless e.message.match? /[34]04/ # 304/404 handled in normal control-flow
        end}

      # update cache
      unless cache.noTransform? || OFFLINE
        begin
          fetchURL[url]                             # HTTPS
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # redirected
          fetchURL[url.sub /^https/, 'http']        # HTTP downgrade
        end
      end

      # response
      if @r # HTTP caller
        if partial_response
          [206, response_meta, [partial_response]]
        elsif cache.exist?
          if cache.noTransform?
            cache.localFile # immutable format
          elsif originUI
            cache.localFile # upstream format
          else              # output transform
            env[:feed] = true if cache.feedMIME?
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script caller
        updates
      end
    rescue OpenURI::HTTPRedirect => re # redirected
      updateLocation re.io.meta['location']
    end

    def filter
      if %w{gif js}.member? ext.downcase # filtered name-suffix
        if ext=='gif' && qs.empty?
          fetch
        else
          deny
        end
      else
        fetch.do{|s,h,b|
          if s.to_s.match? /30[1-3]/ # redirected
            [s, h, b]
          else
            if h['Content-Type'] && !h['Content-Type'].match?(/image.(bmp|gif)|script/)
              [s, h, b]
            else # filtered MIME
              deny
            end
          end}
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
      localNode if localNode?
    end

    # file(s) -> HTTP Response
    def localGraph
      graphResponse localNodes
    end

    def localNode
      if %w{y year m month d day h hour}.member? parts[0] # local timeline
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
        localFile
      else
        localGraph
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def localNode?
      LocalAddr.member? @r['SERVER_NAME']
    end

    PathGET['/log'] = -> r {
      [200, {'Content-Type' => 'text/html'}, [r.htmlDocument(Hosts)]]}

    def metafile type = 'meta'
      dir + (dirname[-1] == '/' ? '' : '/') + '.' + basename + '.' + type
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

    def PUT
      env[:deny] = true
      [202,{},[]]
    end

    # parsed query-string as Hash
    def q
      @q ||= HTTP.parseQs qs[1..-1]
    end

    # query-string
    def qs
      if @r && @r['QUERY_STRING'] && !@r['QUERY_STRING'].empty?
        '?' +  @r['QUERY_STRING']
      elsif query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    # Hash -> String
    def HTTP.qs h
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.intersperse("&").join('')
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

    def remote
      if env.has_key? 'HTTP_TYPE'
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch
          elsif qs == '?allow'
            puts "ALLOW #{uri}"
            env.delete 'QUERY_STRING'
            fetch
          else
            drop
          end
        when /filter/
          filter
        when /thru/
          self.GETthru
        end
      else
        fetch
      end
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
      # TODO mobile/desktop site redirect loops after UA switch prevents 301 (perm) cache
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|twitter|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

  end
  include HTTP
end
