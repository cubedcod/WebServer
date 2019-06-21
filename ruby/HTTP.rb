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

    # env -> accepted formats
    def accept k = 'HTTP_ACCEPT'
      index = {}
      @r && @r[k].do{|v| # header data
        (v.split /,/).map{|e|  # split to (MIME,q) pairs
          format, q = e.split /;/ # split (MIME,q) pair
          i = q && q.split(/=/)[1].to_f || 1.0 # find q-value
          index[i] ||= []              # initialize index-entry
          index[i].push format.strip}} # index on q-value
      index
    end

    # TODO RTFM on CORS/CORB stuff
    def allowedOrigin
      if referer = env['HTTP_REFERER']
        'https://' + referer.R.host
      else
        '*'
      end
    end

    def allowPOST?; host.match? POSThost end

    # cache location
    def cache format=nil
      extension = if format && ext.empty? # format suffix missing but known
                    puts format, RDF::Format.content_types[format]
                    '.' + Extensions[RDF::Format.content_types[format]].to_s
                  else
                    ''
                  end
      ('/' + host + path + extension).R env
    end

    # return cache resource on hit
    def cached?
      return cache if cache.file?      # direct hit
      (cache + '.*').glob.find &:file? # suffix hit
    end

    def self.call env
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? env['REQUEST_METHOD'] # allow methods
      env[:Response] = {}; env[:links] = {}               # response-metadata storage
      path = Pathname.new(env['REQUEST_PATH'].force_encoding('UTF-8')).expand_path.to_s # evaluate pathexp
      query = env[:query] = parseQs env['QUERY_STRING']   # parse query
      resource = ('//' + env['SERVER_NAME'] + path).R env # instantiate requested resource

      # dispatch request
      resource.send(env['REQUEST_METHOD']).do{|status,head,body|
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

        # log request
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

    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ } # entities
      if entities && entities.include?(env[:Response]['ETag']) # client has entity
        [304, {}, []]                            # not modified
      else                                       # generate
        body = generator ? generator.call : self # call generator
        if body.class == WebResource             # static response
          (Rack::File.new nil).serving((Rack::Request.new env), body.localPath).do{|s,h,b| # Rack handler
            if s == 304
              [s, {}, []]                        # not modified
            else
              [s, h.update(env[:Response]), b]   # file
            end}
        else
          [env[:status] || 200, env[:Response], [body]] # generated response
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

    PathGET['/favicon.ico']  = -> r {r.upstreamUI? ? r.fetch : [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}

    def fetch(options = {})
      if this = cached?
        return this.fileResponse
      end

      # request metadata
      @r ||= {}
      head = HTTP.unmangle env                           # strip local headers
      head.delete 'Host'
      head['User-Agent'] = DesktopUA
      head.delete 'User-Agent' if %w{po.st t.co}.member? host
      head[:redirect] = false                            # halt internal redirects
      query = if @r[:query]
                q = @r[:query].dup || {}
                %w{group view sort}.map{|a| q.delete a } # strip local query arguments
                q.empty? ? '' : HTTP.qs(q)               # original query string
              else
                qs
              end
      url = if suffix = ext.empty? && host.match?(/reddit.com$/) && !upstreamUI? && '.rss'
              'https://' + (env['HTTP_HOST'] || host) + path + suffix + query                  # insert format-suffix
            else
              'https://' + (env['HTTP_HOST'] || host) + (env['REQUEST_URI'] || (path + query)) # original URL
            end
      # response metadata
      status = nil
      meta = {}
      body = nil
      format = nil
      file = nil
      graph = options[:graph] || RDF::Repository.new
      @r[:Response] ||= {}

      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3] , ' ' #, url , ' '
        begin
          open(url, head) do |response|
            status = response.status.to_s.match(/\d{3}/)[0]
            meta = response.meta
            %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials ETag Set-Cookie}.map{|k| # read headers
              @r[:Response][k] ||= meta[k.downcase] if meta[k.downcase]}
            format = (meta['content-type'] || 'application/octet-stream').split(/;/)[0]
            if status == 206
              body = response.read                                                                # partial body
            else                                                                                  # complete body
              body = decompress meta, response.read; meta.delete 'content-encoding'               # read body
              puts "caching #{format} from #{url} at #{cache}" unless format.match? RDFformats
              file = (cache format).writeFile body unless format.match? RDFformats                # store non-RDF (RDF stored at named-graph locations when indexing)
              unless %w{application/javascript text/css}.member? format
                reader = RDF::Reader.for(content_type: format)
                if reader
                  reader.new(body, :base_uri => self){|_| graph << _ }                                    # read RDF
                else
                  puts "RDF: no reader for MIME #{format} #{url}" unless format.match? /script/
                end
              end
              RDF::Reader.for(:rdfa).new(body, :base_uri => self){|_| graph << _ } if format=='text/html' # read RDFa
              index graph                                                                                 # index graph
            end
          end
        rescue Exception => e
          case e.message
          when /304/
          # no updates
          when /401/     # unauthorized
            status = 401
          when /403/     # forbidden
            status = 403
          when /404/     # not found
            # set status hint for 404 responses with data from local cache (should we just hide origin 404 and return 200?)
            env[:status] = 404
            status = 404
          else
            raise
          end
        end}

      begin
        fetchURL[url]       #   try HTTPS
      rescue Exception => e # retry network/SSL-related failures on HTTP
        #puts "HTTPS failed: #{e.class} #{e.message} for #{url}"
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
            if options[:no_response]
              puts "REDIRECT \e[32;7m" + location + "\e[0m"
            else
              return updateLocation location
            end
          end
        when 'RuntimeError'
          fetchURL[fallback]
        when 'SocketError'
          fetchURL[fallback]
        else
          raise
        end
      end

      return if options[:no_response] # no HTTP return-value
      if file                  # local static-content
        file.fileResponse
      elsif upstreamUI? && body# remote static-content
        [200, {'Content-Type' => format, 'Content-Length' => body.bytesize.to_s}, [body]]
      elsif 206 == status      # partial static-content
        [status, meta, [body]]
      elsif 304 == status      # not modified
        [304, {}, []]
      elsif [401, 403].member? status
        [status, meta, []]     # authn failure
      else
        graphResponse graph    # content-negotiated graph
      end
    end

    def fileResponse
      @r ||= {}
      @r[:Response] ||= {}
      @r[:Response]['Access-Control-Allow-Origin'] ||= allowedOrigin
      @r[:Response]['ETag'] ||= [uri, mtime, size].join.sha2
      entity
    end

    def GET
      if path.match? /204$/
        [204, {}, []]
      elsif handler = PathGET['/' + parts[0].to_s] # toplevel-path binding
        handler[self]
      elsif handler = PathGET[path] # path binding
        handler[self]
      elsif handler = HostGET[host] # host binding
        handler[self]
      else
        local || remote
      end
    end

    def GETthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      # response
      r = HTTParty.get url, :headers => headers, :body => body
      [r.code, r.headers, [r.body]]
    end

    def graphResponse graph
      return notfound if graph.empty?

      # response metadata
      @r[:Response] ||= {}
      dateMeta if localNode?
      format = selectFormat
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      unless !@r[:links] || @r[:links].empty?
        @r[:Response].update({'Link' => @r[:links].map{|type,uri|
                                "<#{uri}>; rel=#{type}"}.intersperse(', ').join})
      end

      # lazy generator
      entity ->{
        case format
        when /^text\/html/
          if qs == '?data'
            '/mashlib/databrowser.html'.R    # static HTML w/ databrowser sourcecode
          else
            htmlDocument treeFromGraph graph # generated HTML
          end
        when FeedMIME
          renderFeed treeFromGraph graph     # generated feed
        else                                 # RDF
          graph.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true
        end}
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    # stored named-graph(s) in turtle files
    def index g
      updates = []
      g.each_graph.map{|graph|
        if n = graph.name
          n = n.R
          graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value.do{|t| # timestamp
            # doc URI in timeline
            doc = ['/' + t.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),  # hour-dir
                   %w{host path query fragment}.map{|a|n.send(a).do{|p|p.split(/[\W_]/)}},'ttl']. #  slugs
                    flatten.-([nil,'',*BasicSlugs]).join('.').R  # apply skiplist, mint URI
            # store version
            unless doc.e
              doc.dir.mkdir
              RDF::Writer.open(doc.localPath){|f|f << graph}
              updates << doc
              puts  "\e[32m+\e[0m http://localhost:8000" + doc.stripDoc
            else
              #puts  "= http://localhost:8000" + doc.stripDoc
            end
            true}
        else
          #puts "anonymous graph:"
          #puts graph.dump (RDF::Writer.for :turtle).to_sym
        end}
      updates
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
          graph = RDF::Repository.new
          files, dirs = nodes.partition &:file?
          puts dirs
          files.map{|node|
            begin
              graph.load node.localPath, :base_uri => node
            rescue RDF::FormatError => e
              puts [node.localPath, e.class, e.message].join " "
            end
          }
          index graph
          graphResponse graph
        end
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def localNode?; LocalAddr.member?(@r['SERVER_NAME']||host) end

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
              [status, h, b] # allow MIME
            else             # filter MIME
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

    def HTTP.print_header header; header.map{|k,v| puts [k,v].join "\t"} end

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
          elsif q.has_key? 'allow' # allow with stripped querystring
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

    PathGET['/resizer'] = -> r {
      parts = r.path.split /\/\d+x\d+\//
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.remote
      end}

    def selectFormat default = 'text/html'
      accept.sort.reverse.map{|q, formats| # q values in descending order
        formats.map{|mime|
          return default if mime == '*/*'
          return mime if RDF::Writer.for(:content_type => mime) ||          # RDF Writer definition found
                         %w{application/atom+xml text/html}.member?(mime)}} # non-RDF
      default
    end

    def subscribe
      return if subscriptionFile.e
      puts "SUBSCRIBE https:/" + subscriptionFile.dirname
      subscriptionFile.touch
    end

    def subscribed?
      subscriptionFile.exist?
    end
    def subs; puts subscriptions.sort.join ' ' end

    def subscriptions
      subscriptionFile('*').R.glob.map(&:dir).map &:basename
    end

    PathGET['/subscribe'] = -> r {
      url = (r.q['u'] || '/').R
      url.subscribe
      [302, {'Location' => url.to_s}, []]}

    # ALL_CAPS (CGI/env-var) keys to HTTP-capitalization
    # is there a way to have Rack give us this straight out of the HTTP parser?
    def self.unmangle env
      head = {}
      env.map{|k,v|
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split('_').map{|k| # eat prefix and process tokens
          if %w{cl id spf utc xsrf}.member? k # acronyms
            k = k.upcase       # all caps
          else
            k[0] = k[0].upcase # capitalize
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored
        # strip internal headers
        head[key] = v.to_s unless %w{links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}
      head
    end

    def unsubscribe
      subscriptionFile.e && subscriptionFile.node.delete
    end

    PathGET['/unsubscribe']  = -> r {
      url = (r.q['u'] || '/').R
      url.unsubscribe
      [302, {'Location' => url.to_s}, []]}

    def updateLocation location
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|twitter|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

    def upstreamUI?
      if %w{duckduckgo.com soundcloud.com}.member? host
        true
      elsif env['HTTP_USER_AGENT'] == DesktopUA
        true
      else
        false
      end
    end

  end
  include HTTP
  def self.getFeeds
    FeedURL.values.shuffle.map{|feed|
      begin
        feed.fetch format: 'application/atom+xml', no_response: true
      rescue Exception => e
        puts 'https:' + feed.uri, e.class, e.message
      end}
  end
  module URIs

    FeedMIME = /^(application|text)\/(atom|rss|xml)/

    FeedURL = {}
    ConfDir.join('feeds/*.u').R.glob.map{|list|
      list.lines.map{|u| FeedURL[u] = u.R }}

  end
end
