# coding: utf-8
%w(brotli cgi httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    CacheDir = (Pathname.new ENV['HOME'] + '/.cache/web').relative_path_from(Pathname.new Dir.pwd).to_s + '/'
    Hosts = {}   # seen hosts
    HostGET = {} # lambda tables
    PathGET = {}
    Methods = %w(GET HEAD OPTIONS POST)
    OFFLINE = ENV.has_key? 'OFFLINE'

    def allowedOrigin
      if referer = env['HTTP_REFERER']
        'http' + (env['SERVER_NAME'] == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def allowPOST?; host.match? POSThost end

    # cache location
    def cache format=nil
      (CacheDir + (host || 'localhost') +
       ((!path || path[-1] == '/') ? '/index' : (path.size > 127 ? Digest::SHA2.hexdigest(path).yield_self{|p|
                                                                                '/' + p[0..1] + '/' + p[2..-1]} : path)) +
       (qs.empty? ? '' : ('.' + Digest::SHA2.hexdigest(qs))) +
       ((format && ext.empty? && Extensions[RDF::Format.content_types[format]]) ? ('.' + Extensions[RDF::Format.content_types[format]].to_s) : '')).R env
    end

    def cached?
      return false if env && env['HTTP_PRAGMA'] == 'no-cache'
      location = cache
      return location if location.file?     # direct match
      (location + '.*').R.glob.find &:file? # suffix match
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']    # allow methods
      env[:resp] = {}; env[:links] = {}                                  # header storage
      path = Pathname.new(env['REQUEST_PATH']).expand_path.to_s          # evaluate path
      path += '/' if env['REQUEST_PATH'][-1]=='/' && path[-1]!='/'       # preserve trailing-slash
      query = env[:query] = parseQs env['QUERY_STRING']                  # parse query
      resource = ('//' + env['SERVER_NAME'] + path).R env                # instantiate request-resource
      resource.send(env['REQUEST_METHOD']).yield_self{|status,head,body| # dispatch
        color = (if resource.env[:deny]                                  # log
                  '31'                                                   # red -> blocked
                elsif !Hosts.has_key? env['SERVER_NAME']
                  Hosts[env['SERVER_NAME']] = resource
                  '32'                                                   # green -> new host
                elsif env['REQUEST_METHOD'] == 'POST'
                  '32'                                                   # green -> POSTed data
                elsif status == 200
                  if resource.ext=='js' || (head['Content-Type'] && head['Content-Type'].match?(/script/))
                    '36'                                                 # lightblue -> executable
                  else
                    '37'                                                 # white -> basic response
                  end
                else
                  '30'                                                   # gray -> cache hit, NOOP, 304
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

    def dateMeta
      @r ||= {}
      @r[:links] ||= {}
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
      remainder += '/' if @r['REQUEST_PATH'][-1] == '/'
      @r[:links][:prev] = p + remainder + qs + '#prev' if p && p.R.exist?
      @r[:links][:next] = n + remainder + qs + '#next' if n && n.R.exist?
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
      env[:deny] = true
      type, content = if ext == 'js' || env[:script]
                        ['application/javascript',
                         '// TODO deliver modified scripts']
                      elsif path[-3..-1] == 'css'
                        ['text/css',"body {background: repeating-linear-gradient(#{rand 360}deg, #000, #000 6.5em, #fff 6.5em, #fff 8em)\ndiv, p {background-color: #000; color: #fff}"]
                      elsif env[:GIF]
                        ['image/gif', SiteGIF]
                      else
                        ['text/html; charset=utf-8',
                         "<html><body style='#{qs.empty? ? ('background: repeating-linear-gradient(' + (rand 360).to_s + 'deg, #000, #000 6.5em, #f00 6.5em, #f00 8em)') : 'background-color: red'}; text-align: center'><a href='#{qs.empty? ? '?allow' : path}' style='color: #fff; font-weight: bold; font-size: 22em; text-decoration: none'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      head = headers
      body = env['rack.input'].read
      body = if head['Content-Encoding'].to_s.match?(/zip/)
               Zlib::Inflate.inflate(body) rescue ''
             else
               body
             end
      env[:deny] = true
      [202,{},[]]
    end

    def desktop; env['HTTP_USER_AGENT'] = DesktopUA; self end

    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/ # entities
      if entities && entities.include?(env[:resp]['ETag']) # client has entity
        [304, {}, []]                            # not modified
      else                                       # generate
        body = generator ? generator.call : self # call generator
        if body.class == WebResource             # static response
          Rack::File.new(nil).serving(Rack::Request.new(env), body.relPath).yield_self{|s,h,b|
          if s == 304
            [s, {}, []]                          # not modified
          else
            h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type'] == 'application/javascript'
            [s, h.update(env[:resp]), b]     # file response
          end}
        else
          [env[:status] || 200, env[:resp], [body]] # generated response
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

    PathGET['/favicon.ico']  = -> r {r.upstreamUI? ? r.fetch : [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}
    PathGET['/common/js/mashlib.min.js'] = -> r {'/common/js/mashlib.min.js'.R(r.env).fileResponse}

    def fetch options = {} ; @r ||= {}
      if this = cached?; return this.fileResponse end
      graph = options[:graph] || RDF::Repository.new # request graph
      @r['HTTP_ACCEPT'] ||= '*/*'                    # Accept-header default
      hostname = host || @r['SERVER_NAME']           # hostname
      head = headers                                 # headers
      head[:redirect] = false                        # don't internally follow redirects
      options[:cookies] ||= true if hostname.match?(TrackHost) || hostname.match?(POSThost) || hostname.match?(UIhost)
      head.delete 'Cookie' unless options[:cookies]  # allow/deny cookies
      qStr = @r[:query] ? (q = @r[:query].dup        # load query
        %w{group view sort ui}.map{|a|q.delete a}    # consume local arguments
        q.empty? ? '' : HTTP.qs(q)) : qs             # external query
      suffix = ext.empty? && hostname.match?(/reddit.com$/) && !upstreamUI? && '.rss' # format suffix
      u = '//' + hostname + path + (suffix || '') + qStr           # base locator
      url      = (options[:scheme] || 'https').to_s    + ':' + u   # primary locator
      fallback = (options[:scheme] ? 'https' : 'http') + ':' + u   # fallback locator
      options[:content_type]='application/atom+xml' if FeedURL[u]  # fix MIME on feed URLs
      code=nil;meta={};body=nil;format=nil;file=nil;@r[:resp]||={} # response metadata

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' '
        #print url, "\n"; HTTP.print_header head
        begin
          open(url, head) do |response|
            code = response.status.to_s.match(/\d{3}/)[0]
            meta = response.meta
            #print ' ', code, ' ' ; HTTP.print_header meta
            allowed_meta = %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials ETag}
            allowed_meta.push 'Set-Cookie' if options[:cookies]
            allowed_meta.map{|k| @r[:resp][k] ||= meta[k.downcase] if meta[k.downcase]}
            format = options[:content_type] || meta['content-type'] && meta['content-type'].split(/;/)[0]
            format ||= case ext
                       when 'jpg'
                         'image/jpeg'
                       when 'png'
                         'image/png'
                       when 'gif'
                         'image/gif'
                       else
                         'text/html'
                       end
            if code == 206
              body = response.read                                                                 # partial body
            else                                                                                   # complete body
              body = decompress meta, response.read; meta.delete 'content-encoding'                # decompress body
              file = (cache format).writeFile body unless format.match? /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/ # cache non-RDF
              if reader = RDF::Reader.for(content_type: format)
                reader.new(body, :base_uri => url.R){|_| graph << _ } # parse RDF
                index graph                                           # cache RDF
              else
                print "MISSING RDF::Reader for #{format} "
              end
            end
          end
        rescue Exception => e
          case e.message
          when /304/ # no updates
            code = 304
          when /401/ # unauthorized
            code = 401
          when /403/ # forbidden
            code = 403
          when /404/ # not found
            code = 404
          else
            raise
          end
        end}

      begin
        fetchURL[url]       #   try (HTTPS default)
      rescue Exception => e # retry (HTTP)
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
            if options[:no_response]
              puts "REDIRECT #{url} -> \e[32;7m" + location + "\e[0m"
              #HTTP.print_header e.io.meta
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
      end unless OFFLINE

      return if options[:no_response]
      if code == 304                                               # no data
        [304, {}, []]
      elsif file                                                   # data from file
        file.fileResponse
      elsif code == 206                                            # partial data from upstream
        [206, meta, [body]]
      elsif body&&(upstreamUI? || (format.match? ImmutableFormat)) # data from upstream
        [200, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Origin' => allowedOrigin,
               'Content-Type' => format,
               'Content-Length' => body.bytesize.to_s}, [body]]
      else                                                        # graph data
        if graph.empty? && !local? && @r['REQUEST_PATH'][-1]=='/' # unlistable remote
          index = (CacheDir + hostname + path).R                  # local container
          index.children.map{|e| e.fsStat graph, base_uri: 'https://' + e.relPath} if index.node.directory? # list cache
        end
        graphResponse graph
      end
    end

    def fileResponse
      @r ||= {}
      @r[:resp] ||= {}
      @r[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      @r[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def GET
      if path.match? /204$/
        [204, {}, []]
      elsif handler = PathGET['/' + parts[0].to_s] # path binding
        handler[self]
      elsif handler = PathGET[path]
        handler[self]
      elsif handler = HostGET[host]
        handler[self]
      else
        local? ? local : remote
      end
    end

    def graphResponse graph
      return notfound if graph.empty?
      format = selectFormat
      dateMeta if local?
      @r[:resp] ||= {}
      @r[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      @r[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})      
      @r[:resp].update({'Link' => @r[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !@r[:links] || @r[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          if q['ui'] == 'solid'
            ConfDir.join('databrowser.html').R env
          else
            htmlDocument treeFromGraph graph # HTML
          end
        when /^application\/atom+xml/
          renderFeed treeFromGraph graph   # feed
        else                               # RDF
          base = (env['SERVER_NAME']=='localhost' ? 'http://localhost:8000' : ('https://'+host)).R.join env['REQUEST_PATH']
          graph.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => base, :standard_prefixes => true
        end}
    end

    def HEAD
       c,h,b = self.GET
      [c,h,[]]
    end

    # store graph-data in Turtle at index locations derived from graph URI(s)
    def index g
      updates = []
      g.each_graph.map{|graph|
        if n = graph.name
          n = n.R
          docs = []
          # local docs are already stored on timeline (mails/chatlogs in hour-dirs), so we only try for canonical location (messageID, username-derived indexes)
          # canonical location
          docs.push (n.path + '.ttl').R unless n.host || n.uri.match?(/^_:/)
          # timeline location
          if n.host && (timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value)
            docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''), # hour-dir
                       %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # slugs
                        flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist
          end
          # store
          #puts docs
          docs.map{|doc|
            unless doc.exist?
              doc.dir.mkdir
              RDF::Writer.open(doc.relPath){|f|f << graph}
              updates << doc
              puts  "\e[32m+\e[0m http://localhost:8000" + doc.path.sub(/\.ttl$/,'')
            end}
        end}
      updates
    end

    def load graph, options = {}
      if basename.split('.')[0] == 'msg'
        options[:format] = :mail
      elsif ext == 'html'
        options[:format] = :html
      end
      graph.load relPath, options
    end

    def local
      if %w{y year m month d day h hour}.member? parts[0] # timeseg redirect
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
      elsif file?
        fileResponse
      else
        # load RDF
        graph = RDF::Repository.new
        nodes.map{|node|
          node.load graph, base_uri: 'http://localhost:8000/'.R.join(node) if node.file?}
        index graph
        # add node metadata
        nodes.map{|node|
          node.fsStat graph unless node.ext=='ttl' || node.basename.split('.')[0]=='msg' }

        graphResponse graph
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def local?; LocalAddr.member?(@r['SERVER_NAME']||host) end

    # URI -> file(s)
    def nodes
      (if node.directory?
       if q.has_key?('f') && path!='/'    # FIND
         find q['f'] unless q['f'].empty?
       elsif q.has_key?('q') && path!='/' # GREP
         grep q['q']
       else
         index = (self + 'index.{html,ttl}').R.glob
         if !index.empty? && qs.empty?    # static index
           [index]
         else
           [self, children]               # LS
         end
       end
      else                                # GLOB
        if uri.match /[\*\{\[]/           #  parametric glob
          glob
        else                              #  basic glob
          files = (self + '.*').R.glob    #   base + extension match
          files = (self + '*').R.glob if files.empty? # prefix match
          [self, files]
        end
       end).flatten.compact.uniq.select &:exist?
    end

    def noexec
      if %w{gif js}.member? ext.downcase # filtered suffix
        if ext=='gif' && qs.empty? # no querystring, allow GIF
          fetch
        else
          deny
        end
      else # fetch and inspect
        fetch.yield_self{|status, head, body|
          if status.to_s.match? /30[1-3]/ # redirected
            [status, head, body]
          else
            if head['Content-Type'] && !head['Content-Type'].match?(/image.(bmp|gif)|script/)
              [status, head, body] # allowed MIME
            else                   # filtered MIME
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
      #HTTP.print_header head

      # response
      r = HTTParty.post url, :headers => head, :body => body
      code = r.code
      head = r.headers
      body = r.body
      #HTTP.print_header head
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

    # query-string -> Hash
    def q
      @q ||= HTTP.parseQs qs[1..-1]
    end

    # Hash -> query-string
    def HTTP.qs h
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.join("&")
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

    # request for remote resource
    def remote
      if env.has_key? 'HTTP_TYPE' # tagged
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch # music tracks
          elsif q.has_key? 'allow' # allow with stripped querystring
            ['QUERY_STRING', :query].map{|q|env.delete q}
            path.R(env).fetch
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
      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
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
      head['User-Agent'] = DesktopUA
      # try for redirection via HTTP headers, rather than Javascript
      head.delete 'User-Agent' if host == 't.co'
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st'
      head
    end

    def upstreamUI?; !local? && (env['HTTP_USER_AGENT'] == DesktopUA || (host||env['SERVER_NAME']).match?(UIhost) || q['ui'] == 'upstream') end
  end
  include HTTP
end
