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
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, `hostname`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Subdomain = {}

    def allowedOrigin
      if referer = env['HTTP_REFERER']
        'http' + (env['SERVER_NAME'] == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def allowCookies?; hostname = env['SERVER_NAME'] || host || 'localhost'

      ENV.has_key?('COOKIES') ||
        hostname.match?(CookieHost) ||
        hostname.match?(POSThost) ||
        hostname.match?(TrackHost) ||
        hostname.match?(UIhost)
    end

    def allowHost
      env['HTTP_TYPE'] = env['HTTP_TYPE'].split(',').-(%w(dropDNS)).join(',') if env['HTTP_TYPE']
      remote
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

    def cached?
      return false if env && env['HTTP_PRAGMA'] == 'no-cache'
      loc = cache
      return loc if loc.file?     # direct match
      (loc+'.*').R(env).glob.find &:file? # suffix match
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
       env['REQUEST_METHOD'] == 'HEAD' ? [] : [uri.R(env).htmlDocument(
                                                 {uri => {Content => [
                                                            {_: :h3, c: msg.hrefs, style: 'color: red'},
                                                            {_: :pre, c: trace.hrefs},
                                                            (HTML.keyval (Webize::HTML.webizeHash env), env),
                                                            (HTML.keyval (Webize::HTML.webizeHash e.io.meta), env if e.respond_to? :io)]}})]]
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
      puts "Zlib error on #{uri}"
      ''
    end

    def deny status = 200
      HTTP.print_header env if verbose?
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
      if verbose?
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
        @env = e
        self
      else
        @env
      end
    end

    LocalArgs = %w(allow view sort ui)
    def fetch options = {}
      if this = cached?; return this.fileResponse end
      @env ||= {resp: {}}              # init request-meta for non-HTTP callers
      env[:repository] ||= RDF::Repository.new # RDF storage (in-memory)
      env['HTTP_ACCEPT'] ||= '*/*'             # default Accept header
      hostname = env['SERVER_NAME'] || host    # hostname
      HTTP.print_header env if verbose?        # inspect request metadata
      head = headers                           # read request metadata
      head[:redirect] = false                  # don't follow redirects
      qStr = (env[:query] && LocalArgs.find{|arg|env[:query].has_key? arg}) ? (
        q = env[:query].dup                    # read query
        LocalArgs.map{|a|q.delete a}           # consume local args
        q.empty? ? '' : HTTP.qs(q)) : qs       # external query
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
                          #x-iinfo x-iejgwucgyu}
      upstream_metas.push 'Set-Cookie' if allowCookies?

      noTransform = false
      code = nil   # response status
      body = nil   # response body
      format = nil # response format
      file = nil   # response fileref

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' '
        if verbose?
          print url, "\n"
          HTTP.print_header head
        end
        begin
          open(url, head) do |response|
            code = response.status.to_s.match(/\d{3}/)[0]
            meta = response.meta
            if verbose?
              print ' ', code, ' '
              HTTP.print_header meta
            end
            if code == 206
              body = response.read                                         # partial body
              upstream_metas.push 'Content-Encoding'                       # encoding preserved
            else                                                           # complete body
              body = HTTP.decompress meta, response.read                   # decode body
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
                reader.new(body, reader_options){|_| env[:repository] << _ } # read RDF
                index unless options[:no_index]                      # cache+index RDF
              end
            end
            upstream_metas.map{|k| # origin metadata
              env[:resp][k] ||= meta[k.downcase] if meta[k.downcase]}
            HTTP.print_header env[:resp] if verbose?
            puts body if ENV['DEBUG']
          end
        rescue Exception => e
          case e.message # response-types handled in normal control-flow
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
        if e.respond_to? :io
          if verbose?
            puts e.io.status.join ' '
            HTTP.print_header e.io.meta
          end
          body = e.io.read
          puts body if ENV['DEBUG']
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
          if e.respond_to?(:io) && e.io.status.to_s.match?(/999/)
            noTransform = true
            env[:resp] = headers e.io.meta
          else
            fetchURL[fallback]
          end
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
        [206, env[:resp], [body]]
      elsif body && noTransform || (upstreamUI? || (format && (format.match? PreservedFormat))) # upstream data
        [200, env[:resp].merge(body.respond_to?(:bytesize) ? {'Content-Length' => body.bytesize} : {}), [body]]
      else                                                         # graph data
        if env[:repository].empty? && !local? && env['REQUEST_PATH'][-1]=='/' # unlistable remote
          index = (CacheDir + hostname + path).R                              # local container
          index.children.map{|e|e.nodeStat base_uri: 'https://' + e.relPath} if index.node.directory? # local list
        end
        graphResponse
      end
    end

    def GET
      if path.match? /[^\/]204$/
        [204, {}, []] # connect check               lambda lookup:
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

    # header keys from lower-case and CGI_ALL_CAPS to canonical formatting
    def headers hdr = nil
      head = {}

      # read raw headers
      (hdr || env).map{|k,v| # each key
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|k| # eat HTTP prefix from Rack
          if %w{cl id spf utc xsrf}.member? k
            k = k.upcase       # acronymize
          else
            k[0] = k[0].upcase # capitalize token
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored

        # set output header, strip Rack-internal keys
        head[key] = v.to_s unless %w{host links path-info query query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri resp script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)
      }

      # Cookie
      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
      end

      # Referer
      head['Referer'] = 'http://drudgereport.com/' if env['SERVER_NAME']&.match? /wsj\.com/
      head['Referer'] = head['Referer'].sub(/\?ui=upstream$/,'') if head['Referer'] && head['Referer'].match?(/\?ui=upstream$/) # strip local QS TODO remove all local vars

      # User-Agent
      head['User-Agent'] = DesktopUA
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st' # redirect via HTTP header rather than Javascript
      head.delete 'User-Agent' if host == 't.co'            # redirect via HTTP header rather than Javascript

      head
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
        [303, env[:resp].update({'Location' => loc + parts[1..-1].join('/') + qs}), []]
      elsif file? # local file
        fileResponse
      elsif node.directory? && qs.empty? && (index = (self+'index.html').R.env env).exist? && selectFormat == 'text/html'
        index.fileResponse
      else
        localGraph
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(env['SERVER_NAME']||host) end

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
      # origin request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read

      verbose if parts.member? 'graphql'
      if verbose?
        HTTP.print_header head
        HTTP.print_body head, body
      end

      # origin response
      r = HTTParty.post url, :headers => head, :body => body
      code = r.code
      head = r.headers
      body = r.body

      if verbose?
        HTTP.print_header head
        HTTP.print_body head, body
      end

      [code, head, [body]]
    end

    def HTTP.print_body head, body
      body = HTTP.decompress head, body
      body = case head['Content-Type']
             when 'application/json'
               json = ::JSON.parse body
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

    # querystring - late-bound environment takes precedence, dropped '?' if empty
    def qs
      if env && env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
        '?' + env['QUERY_STRING']
      elsif query && !query.empty?
        '?' + query
      else
        ''
      end
    end

    # request for remote resource
    def remote
      if env.has_key? 'HTTP_TYPE' # type-tagged request
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch # music track
          elsif env[:query]['allow'] == ServerKey
            fetch # drop override
          elsif !env[:query].keys.grep(/^utm/).empty?
            [301, {'Location' => env['REQUEST_PATH']}, []]
          else
            deny
          end
        when /noexec/
          noexec
        when /direct/
          r = HTTParty.get ('https://' + host + path + qs), headers: headers
          [r.code, r.headers, [r.body]]
        else
          fetch
        end
      else
        fetch
      end
    rescue OpenURI::HTTPRedirect => e
      [302, {'Location' => e.io.meta['location']}, []]
    end

    def selectFormat default='text/html'
      index = {}
      (env['HTTP_ACCEPT']||'').split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/           # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f|| 1 # q-value with default
        index[i] ||= []                   # index location
        index[i].push format.strip}       # index on q-value

      index.sort.reverse.map{|q,formats| # formats in descending q-value order
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with turtle-preference
          return default if f == '*/*'                        # HTML via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF

      default                                                 # HTML via default
    end

    def upstreamUI?
      !local? && (env['HTTP_USER_AGENT'] == DesktopUA ||
                  env['SERVER_NAME'].match?(UIhost) ||
                  env[:query]['ui'] == 'upstream')
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
