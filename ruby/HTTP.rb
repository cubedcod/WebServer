# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module URIs
    ServerAddr = 'http://l:8000'
  end
  module HTTP
    include URIs
    HostGET = {}
    Hosts = {}
    Methods = %w(GET HEAD OPTIONS POST)
    OffLine = ENV.has_key? 'OFFLINE'
    PathGET = {}
    PreservedFormat = /^(application\/json|audio|font|video)/
    ServerKey = Digest::SHA2.hexdigest [`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join
    Subdomain = {}

    def allowedOrigin
      if referer = env['HTTP_REFERER']
        'http' + (env['SERVER_NAME'] == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def allowCookies?
      hostname = env['SERVER_NAME'] || host || 'localhost'
      hostname.match?(CookieHost) || hostname.match?(TrackHost) || hostname.match?(POSThost) || hostname.match?(UIhost)
    end

    def allowPOST?; host.match? POSThost end

    def cached?
      return false if env && env['HTTP_PRAGMA'] == 'no-cache'
      location = cache
      return location if location.file?     # direct match
      (location + '.*').R.glob.find &:file? # suffix match
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']    # allow HTTP methods
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
             "\e[0m\e[" + color + "m" + env['REQUEST_PATH'] + resource.qs +
             "\e[0m " + (head['Location'] ? (" ↝ " + head['Location']) : '') + ' ' +
             (head['Content-Type'] == 'text/turtle; charset=utf-8' ? '🐢' : (head['Content-Type']||''))

        [status, head, body]} # response
    rescue Exception => e
      uri = 'https://' + env['SERVER_NAME'] + (env['REQUEST_URI']||'')
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts "\e[7;31m500\e[0m " + msg , trace
      [500, {'Content-Type' => 'text/html'},
       env['REQUEST_METHOD'] == 'HEAD' ? [] : [uri.R.htmlDocument(
                                                 {uri => {Content => [
                                                            {_: :h3, c: msg.hrefs, style: 'color: red'},
                                                            {_: :pre, c: trace.hrefs},
                                                            (HTML.keyval (Webize::HTML.webizeHash env), env),
                                                            (HTML.keyval (Webize::HTML.webizeHash e.io.meta), env if e.respond_to? :io)]}})]]
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
    rescue Zlib::DataError
      puts "Zlib error on #{uri}"
      ''
    end

    def deny status = 200
      HTTP.print_header env if host.match? DebugHost
      env[:deny] = true
      type, content = if ext == 'js' || env[:script]
                        ['application/javascript',
                         '// TODO deliver modified scripts']
                      elsif path[-3..-1] == 'css'
                        ['text/css',"body {background: repeating-linear-gradient(#{rand 360}deg, #000, #000 6.5em, #fff 6.5em, #fff 8em)\ndiv, p {background-color: #000; color: #fff}"]
                      elsif env[:GIF]
                        ['image/gif', SiteGIF]
                      else
                        q = env[:query].dup
                        q.keys.map{|k|q.delete k if k.match? /^utm_/}
                        q['allow'] = ServerKey
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{HTTP.qs q}' style='color: #fff; font-weight: bold; font-size: 22em; text-decoration: none'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      if host.match? DebugHost
        HTTP.print_header env
        puts env['rack.input'].read
      end
      env[:deny] = true
      [202,{},[]]
    end

    def desktop; env['HTTP_USER_AGENT'] = DesktopUA; self end

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
        @r = e
        self
      else
        @r
      end
    end

    def fetch options = {}
      if this = cached?; return this.fileResponse end
      @r ||= {resp: {}}; @r['HTTP_ACCEPT'] ||= '*/*' # response-meta storage
      head = headers                                 # read request-meta
      hostname = @r['SERVER_NAME'] || host           # hostname
      head[:redirect] = false                        # don't follow redirects
      options[:cookies] ||= true if allowCookies?
      head.delete 'Cookie' unless options[:cookies]  # allow/deny cookies
      qStr = @r[:query] ? (q = @r[:query].dup        # read query
        %w{allow view sort ui}.map{|a|q.delete a}    # consume local arguments
        q.empty? ? '' : HTTP.qs(q)) : qs             # external query
      suffix = ext.empty? && hostname.match?(/reddit.com$/) && '.rss' # format suffix
      u = '//' + hostname + path + (suffix || '') + qStr          # base locator
      url      = (options[:scheme] || 'https').to_s    + ':' + u  # primary locator
      fallback = (options[:scheme] ? 'https' : 'http') + ':' + u  # fallback locator
      options[:content_type]='application/atom+xml' if FeedURL[u] # fix MIME on feed URLs
      upstream_metas = %w{Access-Control-Allow-Origin
                          Access-Control-Allow-Credentials
                          Content-Type
                          Content-Length
                          ETag}
      upstream_metas.push 'Set-Cookie' if options[:cookies]
      graph = options[:graph] || RDF::Repository.new # response graph
      code = nil   # response status
      body = nil   # response body
      format = nil # response format
      file = nil   # response fileref
      verbose = hostname.match? DebugHost

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' '
        if verbose
          print url, "\n"
          HTTP.print_header head
        end
        begin
          open(url, head) do |response|
            code = response.status.to_s.match(/\d{3}/)[0]
            meta = response.meta
            if verbose
              print ' ', code, ' '
              HTTP.print_header meta
            end
            if code == 206
              body = response.read                                         # partial body
              upstream_metas.push 'Content-Encoding'                       # encoding preserved
            else                                                           # complete body
              body = decompress meta, response.read                        # decode body
              format = options[:content_type] || meta['content-type'] && meta['content-type'].split(/;/)[0]
              format ||= case ext # TODO use RDF->extension mapping table
                         when 'jpg'
                           'image/jpeg'
                         when 'png'
                           'image/png'
                         when 'gif'
                           'image/gif'
                         else
                           'text/html'
                         end
              file = cache(format).write body if !format.match? RDFformats # cache non-RDF
              if reader = RDF::Reader.for(content_type: format)            # RDF reader
                reader_options = {base_uri: url.R, no_embeds: options[:no_embeds]}
                reader.new(body, reader_options){|_| graph << _ }      # parse RDF
                index graph unless options[:no_index]                      # cache RDF
              end
            end
            upstream_metas.map{|k|@r[:resp][k]||=meta[k.downcase] if meta[k.downcase]} # response metadata
          end
        rescue Exception => e
          case e.message # response-types handled in unexceptional control-flow
          when /304/ # no updates
            code = 304
          when /401/ # unauthorized
            code = 401
          when /403/ # forbidden
            code = 403
          when /404/ # not found
            code = 404
          else
            raise # exceptional code
          end
        end}

      begin
        fetchURL[url]       #   try (HTTPS default)
      rescue Exception => e # retry (HTTP)
        if verbose && e.respond_to?(:io)
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
            if options[:no_response]
              puts "REDIRECT #{url} -> \e[32;7m" + location + "\e[0m"
            else
              return [302, {'Location' => location}, []]
            end
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
        [206, @r[:resp], [body]]
      elsif body && (upstreamUI?||format.match?(PreservedFormat)) # upstream data
        [200, @r[:resp].merge({'Content-Length' => body.bytesize}), [body]]
      else                                                        # graph data
        if graph.empty? && !local? && @r['REQUEST_PATH'][-1]=='/' # unlistable remote
          index = (CacheDir + hostname + path).R                  # local container
          index.children.map{|e| e.fsStat graph, base_uri: 'https://' + e.relPath} if index.node.directory? # local list
        end
        graphResponse graph
      end
    end

    def GET
      if path.match? /[^\/]204$/ # connect check
        [204, {}, []]                             # binding lookup
      elsif handler = PathGET['/' + parts[0].to_s] # any host, path-and-children
        handler[self]
      elsif handler = PathGET[path]                # any host, exact path
        handler[self]
      elsif handler = HostGET[host]                # any path, exact host
        handler[self]
      elsif handler = Subdomain[host.split('.')[1..-1].join('.')]
        handler[self]
      else                                         # default
        local? ? local : remote
      end
    end

    def HEAD
       c,h,b = self.GET
      [c,h,[]]
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
        [303, @r[:resp].update({'Location' => loc + parts[1..-1].join('/') + qs}), []]
      elsif file? # local file
        fileResponse
      else
        localGraph
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(@r['SERVER_NAME']||host) end

    def noexec
      if %w{gif js}.member? ext.downcase # filter suffix
        if ext == 'gif' && qs.empty?
          fetch # allow GIFs without query
        else
          deny
        end
      else # fetch
        fetch.yield_self{|status, head, body|
          if status.to_s.match? /30[1-3]/ # redirected
            [status, head, body]
          else # inspect
            if head['Content-Type'] && !head['Content-Type'].match?(/image.(bmp|gif)|script/)
              [status, head, body] # allow MIME
            else                   # filter MIME
              env[:GIF] = true    if head['Content-Type']&.match? /image\/gif/
              env[:script] = true if head['Content-Type']&.match? /script/
              deny status
            end
          end}
      end
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
        [202,{},[]]
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
      # request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read
      if host.match? DebugHost
        HTTP.print_header head
        puts body
      end

      # response
      r = HTTParty.post url, :headers => head, :body => body
      code = r.code
      head = r.headers
      body = r.body
      if host.match? DebugHost
        HTTP.print_header head
        puts body
      end
      [code, head, [body]]
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

    # querystring, late-bound environment takes precedence, drop '?' if empty
    def qs
      if @r && @r['QUERY_STRING'] && !@r['QUERY_STRING'].empty?
        '?' +  @r['QUERY_STRING']
      elsif query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    # request for remote resource
    def remote
      if env.has_key? 'HTTP_TYPE' # tagged
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch # music track
          elsif env[:query]['allow'] == ServerKey
            fetch # drop override
          else
            deny
          end
        when /noexec/
          noexec
        when /direct/
          r = HTTParty.get ('https://' + host + path + qs), headers: headers
          [r.code, r.headers, [r.body]]
        end
      else
        fetch
      end
    rescue OpenURI::HTTPRedirect => e
      [302, {'Location' => e.io.meta['location']}, []]
    end

    def selectFormat
      index = {}
      (env['HTTP_ACCEPT']||'').split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f|| 1   # q-value with default
        index[i] ||= []                     # index location
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats in descending q-value order
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f| # tiebreak
          return f if RDF::Writer.for(:content_type => f) || # RDF writer found
            ['application/atom+xml', 'text/html'].member?(f) # non-RDF writer found
          return 'text/turtle' if f == '*/*' }}              # wildcard writer
      'text/html'                                            # default writer
    end

    # convert ALLCAPS CGI vars to HTTP capitalization
    def headers
      head = {}
      env.map{|k,v|
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split('_').map{|k| # eat prefix
          if %w{cl id spf utc xsrf}.member? k # all-cap acronyms
            k = k.upcase
          else
            k[0] = k[0].upcase
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored

        # set external headers
        head[key] = v.to_s unless %w{host links path-info query query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri resp script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}

      head['Referer'] = 'http://drudgereport.com/' if env['SERVER_NAME']&.match? /wsj\.com/
      head['User-Agent'] = DesktopUA unless host && (host.match? UAhost)

      # try for redirection via HTTP headers, rather than Javascript
      head.delete 'User-Agent' if host == 't.co'
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st'

      # unmangled headers
      head
    end

    def upstreamUI?
      !local? && (env['HTTP_USER_AGENT'] == DesktopUA ||
                  env['SERVER_NAME'].match?(UIhost) ||
                  env[:query]['ui'] == 'upstream')
    end
  end
  include HTTP
end
