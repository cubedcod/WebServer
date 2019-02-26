# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    def cache?; !(pragma && pragma == 'no-cache') end

    def cachedRedirect
      verbose = false
      scheme = 'http' + (InsecureShorteners.member?(host) ? '' : 's') + '://'
      sourcePath = path || ''
      source = scheme + host + sourcePath
      dest = nil
      cache = ('/cache/URL/' + host + (sourcePath[0..2] || '') + '/' + (sourcePath[3..-1] || '') + '.u').R
      puts "redir #{source} ->" if verbose

      if cache.exist?
        puts "cached at #{cache}" if verbose
        dest = cache.readFile
      else
        resp = Net::HTTP.get_response (URI.parse source)
        dest = resp['Location'] || resp['location']
        if !dest
          body = Nokogiri::HTML.fragment resp.body
          refresh = body.css 'meta[http-equiv="refresh"]'
          if refresh && refresh.size > 0
            content = refresh.attr('content')
            if content
              dest = content.to_s.split('URL=')[-1]
            end
          end
        end
        cache.writeFile dest if dest
      end

      puts dest if verbose
      dest = dest ? dest.R : nil
      if @r
        # return URI to caller in document
        # [200, {'Content-Type' => 'text/html'}, [htmlDocument({source => {Link => dest}})]]
        # redirect to URI
        dest ? [302, {'Location' =>  dest},[]] : notfound
      else
        dest
      end
    end

    def self.call env
      method = env['REQUEST_METHOD']
      return [202,{},[]] unless Methods.member? method
      query = parseQs env['QUERY_STRING']
      host = query['host'] || env['HTTP_HOST'] || 'localhost'
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse consecutive slashes
      path  = Pathname.new(rawpath).expand_path.to_s # evaluate path-expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/' # trailing-slash preservation
      resource = ('//' + host + path).R env # bind resource and environment
      resource.send(method).do{|status,head,body| # dispatch request
        # log request
        color = (if resource.env[:deny]
                 '31'
                elsif method=='POST'
                  '32'
                elsif status==200
                  '37'
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
        location = head['Location'] ? (" -> " + head['Location']) : ""
        puts "\e[7m" + (method == 'GET' ? ' ' : '') + method + "\e[" +
             color + "m "  + status.to_s + "\e[0m " +
             referrer + "\e[" + color + ";7mhttps://" +
             host + "\e[0m\e[" + color + "m" + path + resource.qs + "\e[0m" +
             location

        [status, head, body]
      }
    rescue Exception => x
      [500, {'Content-Type'=>'text/plain'}, method=='HEAD' ? [] : [[x.class,x.message,x.backtrace].join("\n")]]
    end

    def chronoDir?
      (parts[0]||'').match /^(y(ear)?|m(onth)?|d(ay)?|h(our)?)$/i
    end

    def chronoDir
      time = Time.now
      loc = time.strftime(case parts[0][0].downcase
                          when 'y'
                            '%Y'
                          when 'm'
                            '%Y/%m'
                          when 'd'
                            '%Y/%m/%d'
                          when 'h'
                            '%Y/%m/%d/%H'
                          else
                          end)
      [303, @r[:Response].update({'Location' => '/' + loc + '/' + parts[1..-1].join('/') + qs}), []]
    end

    def cloudStorage
      if UpstreamToggle[@r['SERVER_NAME']] || StoreItAll.member?(host) || MediaFormats.member?(ext.downcase)
        remoteNode
      else
        deny
      end
    end

    def dateMeta
      @r ||= {}
      @r[:links] ||= {}
      dp = [] # date parts
      dp.push parts.shift.to_i while parts[0] && parts[0].match(/^[0-9]+$/)
      n = nil; p = nil
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
      # preserve trailing slash
      sl = parts.empty? ? '' : (path[-1] == '/' ? '/' : '')

      # add pointers to HTTP response header
      @r[:links][:prev] = p + '/' + parts.join('/') + sl + qs + '#prev' if p && p.R.e
      @r[:links][:next] = n + '/' + parts.join('/') + sl + qs + '#next' if n && n.R.e
      @r[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs + '#r' + (path||'/').sha2 unless !path || path=='/'
    end

    def deny
      env[:deny] = true
      ConfDir.join('squid/ERR_ACCESS_DENIED').R(env).setMIME('text/html').fileResponse
    end

    def emptyJS
      [200, {'Content-Type' => 'application/javascript'}, []]
    end

    # conditional responder
    def entity env, lambda = nil
      etags = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ }
      if etags && (etags.include? env[:Response]['ETag'])
        [304, {}, []] # client has entity
      else
        body = lambda ? lambda.call : self # response body
        if body.class == WebResource # resource reference
          # dispatch to file handler
          (Rack::File.new nil).serving((Rack::Request.new env),body.localPath).do{|s,h,b| # response
            [s,h.update(env[:Response]),b]} # attach metadata and return
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

    def GET
      @r[:Response] = {} # response headers
      @r[:links] = {}    # graph-level references
      return PathGET[path][self] if PathGET[path] # dispatch to lambda binding (path name)
      return HostGET[host][self] if HostGET[host] # dispatch to lambda binding (host name)
      return case env['HTTP_TYPE'] # dispatch on request type-tag attached upstream
             when /AMP/
               amp
             when /shortened/
               cachedRedirect
             when /storage/
               cloudStorage
             else
               deny
             end if env.has_key? 'HTTP_TYPE'
      return chronoDir if chronoDir? # time-seg redirect
      return fileResponse if node.file? # static-data response
      if localResource?
        graphResponse localNodes
      else
        remoteNode
      end
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    HeaderAcronyms = %w{cl id spf utc xsrf}
    InternalHeaders = %w{accept-encoding feedurl links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software track unicorn.socket upgrade-insecure-requests version via x-forwarded-for}

    def localResource?
      !q.has_key?('host') && %w{l [::1] 127.0.0.1 localhost}.member?(@r['SERVER_NAME'])
    end

    Methods = %w{GET HEAD OPTIONS PUT POST}

    def notfound
      dateMeta # page hints as something nearby may exist
      [404,{'Content-Type' => 'text/html'},[htmlDocument]]
    end

    def OPTIONS
      return HostOPTIONS[host][self] if HostOPTIONS[host]
      [202,{},[]]
    end

    def OPTIONSthru
      verbose = false

      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      HTTP.print_header headers if verbose
      HTTP.print_body body, headers['Content-Type'] if verbose

      # response
      r = HTTParty.options url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      HTTP.print_header h if verbose
      HTTP.print_body b, h['Content-Type'] if verbose
      [s, h, [b]]
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

    def POST
      return PathPOST[path][self] if PathPOST[path]
      return HostPOST[host][self] if HostPOST[host]
      trackPOST
    end

    # uncached pass-through POST
    def POSTthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      #HTTP.print_header headers
      #HTTP.print_body body, headers['Content-Type']

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      #HTTP.print_header h
      #HTTP.print_body b, h['Content-Type']
      [s, h, [b]]
    end

    def pragma; env['HTTP_PRAGMA'] end

    def HTTP.print_body body, mime
      case mime
      when /application\/json/
        puts ::JSON.pretty_generate ::JSON.parse body
      when /application\/x-www-form-urlencoded/
        q = HTTP.parseQs body
        message = q.delete "message"
        puts q
        puts ::JSON.pretty_generate ::JSON.parse message if message
      else
        puts body
      end
    rescue ::JSON::ParserError
      nil
    end

    def print_body
      @r['rack.input'].do{|i|
        HTTP.print_body i.read, @r['CONTENT_TYPE'] }
    end

    def HTTP.print_header header
      header.map{|k,v|
        puts [k,v].join "\t"}
    end

    def print_header
      HTTP.print_header env
    end

    def PUT
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
      elsif        query          && !query.empty?
        '?' +      query
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

    def remoteNode
      head = HTTP.unmangle env
      head.delete 'Host'
      formatSuffix = (host.match?(/reddit.com$/) && !parts.member?('w')) ? '.rss' : ''
      useExtension = %w{aac atom css html jpg js mp3 mp4 pdf png rdf svg ttf ttl webm webp woff woff2}.member? ext.downcase
      portNum = port && !([80,443,8000].member? port) && ":#{port}" || ''
      queryHash = q
      queryHash.delete 'host'
      queryString = queryHash.empty? ? '' : (HTTP.qs queryHash)
      # origin URI
      urlHTTPS = scheme && scheme=='https' && uri || ('https://' + host + portNum + path + formatSuffix + queryString)
      urlHTTP  = 'http://'  + host + portNum + (path||'/') + formatSuffix + queryString
      # local URI
      cache = ('/' + host + (if FlatMap.member?(host) || (qs && !qs.empty?) # mint a path
                             hash = ((path||'/') + qs).sha2          # hash origin path
                             type = useExtension ? ext : 'cache' # append suffix
                             '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # plunk in semi-balanced bins
                            else # preserve upstream path
                              name = path[-1] == '/' ? path[0..-2] : path # strip trailing-slash
                              name + (useExtension ? '' : '.cache') # append suffix
                             end)).R env
      cacheMeta = cache.metafile

      # lazy updater, called by need
      updates = []
      update = -> url {
        begin # block to catch 304-response "error"
          puts "fetch #{url}"
          # conditional GET
          open(url, head) do |response| # response

            if @r # HTTP-request calling context - preserve origin bits
              @r[:Response]['Access-Control-Allow-Origin'] ||= '*'
              response.meta['set-cookie'].do{|cookie| @r[:Response]['Set-Cookie'] = cookie}
            end

             # index updates
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # cache body
              mime = response.meta['content-type'].do{|type| type.split(';')[0] } || ''
              cacheMeta.writeFile [mime, url, ''].join "\n" unless useExtension
              # index content
              updates.concat(case mime
                             when /^application\/atom/
                               cache.indexFeed
                             when /^application\/rss/
                               cache.indexFeed
                             when /^application\/xml/
                               cache.indexFeed
                             when /^text\/html/
                               if feedURL? # HTML typetag on specified feed URL
                                 cache.indexFeed
                               else
                                 cache.indexHTML host
                               end
                             when /^text\/xml/
                               cache.indexFeed
                             else
                               []
                             end || [])
            end
          end
        rescue OpenURI::HTTPError => e
          raise unless e.message.match? /304/
        end}

      # conditional update
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
        begin # prefer HTTPS w/ fallback HTTP attempt
          update[urlHTTPS]
        rescue
          update[urlHTTP]
        end
        cacheMeta.touch if cacheMeta.e # bump timestamp
      end

      # response
      if @r # HTTP calling context
        if cache.exist?
          # preserve upstream format?
          if UpstreamToggle[@r['SERVER_NAME']] || UpstreamFormat.member?(@r['SERVER_NAME']) || cache.noTransform?
            cache.fileResponse
          else # transformable
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script/shell caller
        updates.empty? ? self : updates
      end

    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts msg, trace
      @r ? [500, {'Content-Type' => 'text/html'},
            [htmlDocument({uri => {Content => [{_: :style, c: "body {background-color: red !important}"},
                                               {_: :h3, c: msg.hrefs}, {_: :pre, c: trace.hrefs},
                                               {_: :h4, c: 'request'},
                                               (HTML.kv (HTML.urifyHash head), @r), # request header
                                               ([{_: :h4, c: "response #{e.io.status[0]}"},
                                                (HTML.kv (HTML.urifyHash e.io.meta), @r), # response header
                                                (CGI.escapeHTML e.io.read.to_utf8)] if e.respond_to? :io) # response body
                                              ]}})]] : self
    end

    Response_204 = [204, {'Content-Length' => 0}, []]

    def trackPOST
      env[:deny] = true
      [202,{},[]]
    end

    def self.unmangle env
      head = {}
      env.map{|k,v|
        key = k.to_s.downcase.sub(/^http_/,'').split('_').map{|k|
          if HeaderAcronyms.member? k
            k = k.upcase
          else
            k[0] = k[0].upcase
          end
          k
        }.join '-'
        head[key] = v.to_s unless InternalHeaders.member?(key.downcase)}
      head
    end

  end
  include HTTP
end
