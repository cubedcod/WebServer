# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs
    AllowedHosts = {}
    HostGET = {}
    HostPOST = {}
    Hosts = {}
    LocalArgs = %w(allow view sort ui)
    Methods = {'GET' => :GETrequest,
              'HEAD' => :HEAD,
              'OPTIONS' => :OPTIONS,
              'POST' => :POSTrequest}
    OffLine = ENV.has_key? 'OFFLINE'
    PathGET = {}
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
        color = (if resource.env[:deny]                          # log request
                  '31'                                           # red -> denied
                elsif !Hosts.has_key? env['SERVER_NAME']
                  Hosts[env['SERVER_NAME']] = resource
                  '32'                                           # green -> new host
                elsif env['REQUEST_METHOD'] == 'POST'
                  '32'                                           # green -> POST
                elsif status == 200
                  if resource.ext=='js' || (head['Content-Type'] && head['Content-Type'].match?(/script/))
                    '36'                                         # lightblue -> executable
                  else
                    '37'                                         # white -> basic response
                  end
                else
                  '30'                                           # gray -> cache-hit, 304, NOOP
                end) + ';1'
        ext = resource.ext.downcase
        mime = head['Content-Type'] || ''

        if resource.env[:deny]
          print '🛑'
        elsif status == 304
          print '✅'
        elsif ext == 'css'
          print '🎨🖍️'[rand 2]
        elsif %w(gif jpeg jpg).member? ext
          print '🖼️'
        elsif %w(png svg webp).member?(ext) || mime.match?(/^image/)
          print '🖌'
        elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
          print '🔉'
        elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
          print '🎬'
        else
          print '🌍🌎🌏🌐'[rand 4] if !resource.local?
          puts "\e[7m" + (env['REQUEST_METHOD'] == 'GET' ? '' : env['REQUEST_METHOD']) +
               "\e[" + color + "m"  + (status == 200 ? '' : status.to_s) + (env['HTTP_REFERER'] ? (' ' + (env['HTTP_REFERER'].R.host || '').sub(/^www\./,'').sub(/\.com$/,'') + "\e[0m→") : ' ') +
               "\e[" + color + ";7m https://" + env['SERVER_NAME'] + "\e[0m\e[" + color + "m" + env['REQUEST_PATH'] + (env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || '') +
               "\e[0m" + (head['Location'] ? ("➡️" + head['Location']) : '') + ' ' + (head['Content-Type'] == 'text/turtle; charset=utf-8' ? '🐢' : mime)
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
      env[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs unless !path || path == '/'
      env[:links][:down] = path + '/' if env['REQUEST_PATH'] && node.directory? && env['REQUEST_PATH'][-1] != '/'
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
      return [301,{'Location'=>env['REQUEST_PATH']},[]] if env['REQUEST_URI'].match?(/\.png\?/) || !env[:query].keys.grep(/campaign|[iu]tm_/).empty?

      env[:deny] = true
      type, content = if ext == 'js' || type == :script
                        source = SiteDir.join 'alternatives/' + host + path
                        ['application/javascript', source.exist? ? source.read : '//']
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
      env[:deny] = true
      HTTP.print_body head, HTTP.decompress(head, env['rack.input'].read.force_encoding('UTF-8')) if verbose?
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    def desktop; env['HTTP_USER_AGENT'] = DesktopUA[0]; self end

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

    # fetch remote. potentially non-HTTP transports but HTTPS + HTTP for now
    def fetch options = {}
      return [304, {}, []] if env.has_key?('HTTP_IF_NONE_MATCH') && (%w(css gif jpeg jpg js mp3 mp4 png svg webm webp).member?(ext.downcase)||host.match?(/ggpht.com$/))
      u = '//' + hostname + path + (options[:suffix]||'') + qs           # URI sans scheme
      primary  = ((options[:scheme] || 'https').to_s + ':' + u).R env    # primary locator
      fallback = ((options[:scheme] ? 'https' : 'http') + ':' + u).R env # fallback locator
      primary.fetchHTTP   #   try HTTPS
    rescue Exception => e # retry HTTP
      case e.class.to_s
      when 'OpenURI::HTTPRedirect' # redirected
        if fallback == e.io.meta['location']
          fallback.fetchHTTP       # only the transport changed, follow redirect
        elsif env[:intermedate]    # no HTTP-response finisher
          puts "RELOC #{uri} -> #{e.io.meta['location']}" # alert caller for updated locatiin
          e.io.meta['location'].R(env).fetchHTTP # follow redirection
        else                       # update caller with new location via HTTP
          [302, {'Location' => e.io.meta['location']}, []]
        end
      when 'Errno::ECONNREFUSED'
        fallback.fetchHTTP
      when 'Errno::ECONNRESET'
        fallback.fetchHTTP
      when 'Errno::ENETUNREACH'
        fallback.fetchHTTP
      when 'Net::OpenTimeout'
        fallback.fetchHTTP
      when 'Net::ReadTimeout'
        fallback.fetchHTTP
      when 'OpenSSL::SSL::SSLError'
        fallback.fetchHTTP
      when 'OpenURI::HTTPError'
        fallback.fetchHTTP
      when 'RuntimeError'
        fallback.fetchHTTP
      when 'SocketError'
        fallback.fetchHTTP
      else
        raise
      end
    end

    # fetch over HTTP
    def fetchHTTP

      if verbose? # logging
        puts  "\e[7mREQUEST HEADER\e[0m IN"
        HTTP.print_header env
        puts  "\e[7mREQUEST HEADER\e[0m OUT"
        HTTP.print_header headers
      end

      open(uri, headers.merge({redirect: false})) do |response|          # fetch
        env[:scheme] = scheme                                            # request scheme
        status = response.status.to_s.match(/\d{3}/)[0].to_i             # upstream status
        meta = response.meta                                             # upstream metadata

        if verbose? # logging
          puts "GET #{status} #{uri}\n\n"
          puts  "\e[7mRESPONSE HEADER\e[0m IN"
          HTTP.print_header meta
        end

        if status == 206                                                 # partial body
          [status, meta, [response.read]]                                # return partial body
        else                                                             # body
          format = env && env[:content_type]                             # explicit format-argument
          format ||= meta['content-type'].split(/;/)[0] if meta['content-type'] # format specified in header
          format ||= (xt = ext.to_sym                                    # path-extension -> format map
            RDF::Format.file_extensions.has_key?(xt) && RDF::Format.file_extensions[xt][0].content_type[0])

          body = HTTP.decompress meta, response.read                     # decode body

          env[:repository] ||= RDF::Repository.new                       # RDF storage
          RDF::Reader.for(content_type: format).yield_self{|reader|      # RDF reader
            reader.new(body, {base_uri: self, no_embeds: env[:no_RDFa]}){|rdf|
              env[:repository] << rdf } if reader}                       # parse RDF

          return self if env[:intermediate]                              # no response?

          index                                                          # index RDF

          if verbose? # logging
            puts  "\e[7mRESPONSE HEADER\e[0m OUT"
            HTTP.print_header env[:resp]
          end

          # metadata for HTTP caller
          %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag Set-Cookie}.map{|k|
            env[:resp][k] ||= meta[k.downcase] if meta[k.downcase]}
          env[:resp]['Content-Length'] = body.bytesize.to_s

          env[:transform] ||= !(upstreamFormat? format)                  # rewritable?
          env[:transform] ? graphResponse : [status, env[:resp], [body]] # return RDF or upstream-data
        end
      end
    rescue Exception => e
      case e.message
      when /304/ # not modified
        print '✅'; [304, {}, []]
      when /401/ # unauthorized
        print '🚫'; notfound
      when /403/ # forbidden
        print '🚫'; notfound
      when /404/ # not found
        print '❓'; env[:intermediate] ? (print uri) : notfound
      when /500/ # server error
        print '🛑'; notfound
      when /503/ #
        print '🛑'; notfound
      when /999/ # (nonstandard)
        [999, e.io.meta, [e.io.read]]
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def self.GET arg, lambda
      HostGET[arg] = lambda
    end

    def GETrequest
      if path.match? /[^\/]204$/                   # connectivity-check
        env[:deny] = true
        [204, {}, []]
      elsif handler = HostGET[host]                # host binding
        handler[self]
      elsif gunk?
        deny
      elsif local?                                 # local resource
        local
      else                                         # global resource
        fetch
      end
    rescue OpenURI::HTTPRedirect => e
      [302,{'Location' => e.io.meta['location']},[]]
    end

    # Graph -> HTTP Response
    def graphResponse
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
          base = ((env[:scheme] || 'https') + '://' + env['SERVER_NAME']).R.join env['REQUEST_PATH']
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => base, :standard_prefixes => true
        end}
    end

    def gunk?
      gunkHost? || gunkURI?
    end

    def gunkHost?
      return false if AllowedHosts.has_key? host        # host allow
      return false if env[:query]['allow'] == ServerKey # temporary allow
      return true unless env['REQUEST_METHOD'] == 'GET' # write methods default to deny
      env.has_key? 'HTTP_GUNK'
    end

    def gunkURI?
      return false if env[:query]['allow'] == ServerKey # temporary allow
      ('//' + env['SERVER_NAME'] + env['REQUEST_URI']).match? GunkURI
    end

    def HEAD
       c,h,b = self.GETrequest
      [c,h,[]]
    end

    # header keys from lower-case and CGI_ALL_CAPS to canonical formatting
    def headers hdr = nil
      head = {} # external headers

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

        # set external headers
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
      head['User-Agent'] = DesktopUA[0]
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st'
      head.delete 'User-Agent' if host == 't.co'

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
        [303, env[:resp].update({'Location' => loc + parts[1..-1].join('/') + (env['QUERY_STRING'] && !env['QUERY_STRING'].empty? && ('?'+env['QUERY_STRING']) || '')}), []]
      elsif path == '/mail' # inbox redirect
        [302, {'Location' => '/d/*/msg*?head&sort=date&view=table'}, []]
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
#        index             # index non-RDF
        rdf.map &:load    # load  RDF
        dateMeta
        graphResponse     # response
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(env['SERVER_NAME']) || ENV['SERVER_NAME'] == env['SERVER_NAME'] end

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

    def notfound
      dateMeta # nearby nodes may exist, search for pointers
      [404, {'Content-Type' => 'text/html'}, [htmlDocument]]
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

    def POSTrequest
      if handler = HostPOST[host] # host handler
        handler[self]
      else
        return denyPOST if gunk?
        self.POSTthru
      end
    end

    def POSTthru
      # origin request
      url = 'https://' + host + path + qs
      head = headers
      body = env['rack.input'].read

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
      head.delete 'connection'
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
             puts json['query'] if json['query']
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

    # serialize external querystring
    def qs
      if env
        if env[:intermediate] && env[:query]
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

    def upstreamFormat? format = nil
      return true if DesktopUA.member?(env['HTTP_USER_AGENT']) || parts.member?('embed') || host.split('.').member?('oembed')
      return false if !format || (format.match? /\/(atom|rss)/i)
      format.match? NoTransform
    end

    def verbose?
      ENV.has_key? 'VERBOSE'
    end

  end
  include HTTP
end
