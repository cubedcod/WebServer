# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    AllowedHosts = {}
    CookieHosts = {}
    GlobChars = /[\*\{\[]/
    HostGET = {}
    HostPOST = {}
    HTTPHosts = {}
    LocalArgs = %w(allow view sort UX)
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Populator = {}
    Req204 = /gen(erate)?_?204$/
    Servers = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert
    Internal_Headers = %w(
connection gunk host keep-alive links path-info query-string
rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rdf refhost remote-addr repository request-method request-path request-uri resp
script-name server-name server-port server-protocol server-software site-chrome sort
te transfer-encoding
unicorn.socket upgrade upgrade-insecure-requests ux version via x-forwarded-for
)

    # handlers
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.query_values&.has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.query_values['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['q'])}, []]}
    NoGunk  = -> r {r.gunkURI && (r.query_values || {})['allow'] != ServerKey && r.deny || r.fetch}
    NoQuery = -> r {
      if !r.query                         # request without query
        NoGunk[r].yield_self{|s,h,b|      #  inspect response
          h.keys.map{|k|                  #  strip query from new location
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                        #  response
      else                                # request with query
        [302, {'Location' => r.path}, []] #  redirect to path
      end}

    RootIndex = -> r {
      if r.path == '/' || r.path.match?(GlobChars)
        r.nodeResponse
      else
        r.chrono_sort if r.parts.size == 1
        NoGunk[r]
      end}

    R204 = [204, {}, []]
    R304 = [304, {}, []]

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      @cookies || AllowedHosts.has_key?(host) || CookieHosts.has_key?(host) || CookieHost.match?(host)
    end

    def allowCDN?
      (CacheExt - %w(html js)).member?(ext.downcase) && !path.match?(Gunk)
    end

    def allowedOrigin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']           # allow HTTP methods
      uri = RDF::URI('https://' + env['HTTP_HOST']).join env['REQUEST_PATH']
      uri.query = env['QUERY_STRING'] if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
      resource = uri.R env                                                      # instantiate request
      env[:refhost] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}                                                           # response-header storage
      env[:links] = {}                                                          # Link response-header
      if uri.query_values&.has_key? 'full'
        env[:links][:up] = '?'
      elsif uri.path != '/'
        up = File.dirname uri.path
        up += '/' unless up == '/'
        up += '?' + uri.query if uri.query
        env[:links][:up] = up
      end
      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch

        ext = resource.path ? resource.ext.downcase : ''                        # log
        mime = head['Content-Type'] || ''

        print "\n"
        unless (Servers.has_key? resource.host) || resource.env[:deny]
          Servers[resource.host] = true
          print "➕ \e[36;7;1m" + resource.uri + "\e[0m "        # log host on first visit
        end
        print status, ' ' unless status == 200

        if resource.env[:deny]
          print (env['REQUEST_METHOD'] == 'POST' ? "\e[31;7;1m📝 " : "🛑 \e[31;1m") + (env[:refhost] ? ("\e[7m" + env[:refhost] + "\e[0m\e[31;1m → ") : '') + (env[:refhost] == resource.host ? '' : ('http://' + resource.host)) + "\e[7m" + resource.path + "\e[0m\e[31m" + "\e[0m "

        # OPTIONS
        elsif env['REQUEST_METHOD'] == 'OPTIONS'
          print "🔧 \e[32;1m#{resource.uri}\e[0m "

        # POST
        elsif env['REQUEST_METHOD'] == 'POST'
          print "📝 \e[32;1m#{resource.uri}\e[0m "

        # non-content response
        elsif [301, 302, 303].member? status                     # redirect
          print resource.uri ," ➡️  ", head['Location']
        elsif [204, 304].member? status                          # up-to-date
          print '✅'
        elsif status == 404                                      # not found
          print "❓ #{resource.uri} " unless resource.path == '/favicon.ico'
        elsif status == 410
          print "❌ #{resource.uri} "

        # content response
        elsif ext == 'css'                                       # stylesheet
          print '🎨'
        elsif ext == 'js' || mime.match?(/script/)               # script
          print "📜 \e[36;1mhttps://" + resource.host + resource.path + "\e[0m "
        elsif ext == 'json' || mime.match?(/json/)               # data
          print "🗒 " + resource.uri
        elsif %w(gif jpeg jpg png svg webp).member?(ext) || mime.match?(/^image/)
          print '🖼️'                                              # image
        elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
          print '🔉'                                             # audio
        elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
          print '🎬'                                             # video
        elsif ext == 'ttl' || mime == 'text/turtle; charset=utf-8'
          print '🐢'                                             # turtle

        else # default log
          print (mime.match?(/html/) ? '📃' : mime) + (env[:repository] ? (('%5d' % env[:repository].size) + '⋮ ') : '') + "\e[7m" + resource.uri + "\e[0m "
        end
        
        [status, head, body]} # response
    rescue Exception => e
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

    def self.Cookies host
      CookieHosts[host] = true
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
      type, content = if type == :stylesheet || ext == 'css'
                        ['text/css', '']
                      elsif type == :font || %w(eot otf ttf woff woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(gif png).member?(ext)
                        ['image/gif', SiteGIF]
                      elsif type == :script || ext == 'js'
                        source = SiteDir.join 'alternatives/' + host + path
                        ['application/javascript', source.exist? ? source.read : '//']
                      elsif type == :JSON || ext == 'json'
                        ['application/json','{}']
                      else
                        q = query_values || {}
                        q['allow'] = ServerKey
                        ['text/html; charset=utf-8',
                         "<html><body style='background: repeating-linear-gradient(#{(rand 360).to_s}deg, #000, #000 6.5em, #f00 6.5em, #f00 8em); text-align: center'><a href='#{HTTP.qs q}' style='color: #fff; font-size: 22em; font-weight: bold; text-decoration: none'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowedOrigin,
        'Content-Type' => type},
       [content]]
    end

    def denyPOST
      env[:deny] = true
      HTTP.print_body headers, env['rack.input'].read if ENV.has_key? 'VERBOSE'
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env
      end
    end

    # fetch node from cache or remote server
    def fetch options=nil
      options ||= {}

      # cached results TODO Find static resource when ext changed due to erroneous upstream MIME or extension
      if (CacheExt - %w(json html xml)).member?(ext.downcase) && !host.match?(DynamicImgHost)
        return R304 if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client has static-data, return 304 response
        return fileResponse if node.file?                            # server has static-data, return data
      end

      # construct locator
      qs = if options[:query]                                        # query string
             HTTP.qs options[:query]
           elsif query
             '?' + query
           else
             ''
           end
      u = ['//', host, (port ? [':', port] : nil), path, options[:suffix], qs].join # base locator
      primary  = ('https:' + u).R env # primary locator
      fallback = ('http:' + u).R env  # fallback locator

      # network fetch
      primary.fetchHTTP options
    rescue Exception => e
      case e.class.to_s
      when 'Errno::ECONNREFUSED'
        fallback.fetchHTTP options
      when 'Errno::ECONNRESET'
        fallback.fetchHTTP options
      when 'Errno::EHOSTUNREACH'
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

    def fetchHTTP options = {}
      print "\n🐕  #{uri} " #if ENV.has_key? 'VERBOSE'
      # TODO set if-modified-since/etag headers from local cache contents (eattr support sufficient for etag metadata?)
      URI.open(uri, headers.merge({redirect: false})) do |response|
        h = response.meta                                             # upstream metadata
        if response.status.to_s.match? /206/                          # partial response
          h['Access-Control-Allow-Origin'] = allowedOrigin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                                   # return part downstream
        else
          body = HTTP.decompress h, response.read                     # decompress body
          format = if path == '/feed' || (query_values||{})['mime']=='xml'   # content-type
                     'application/atom+xml'
                   elsif h.has_key? 'content-type'
                     h['content-type'].split(/;/)[0]
                   elsif RDF::Format.file_extensions.has_key? ext.to_sym
                     puts "ENOTYPE on #{uri} , pathname determines MIME"
                     RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
                   end
          static = !options[:reformat] && (fixedFormat? format)       # rewritable format?
          body = Webize::HTML.degunk body, static if format == 'text/html' && !AllowedHosts.has_key?(host) # clean HTML
          formatExt = Suffixes[format] || Suffixes_Rack[format] || (puts "ENOSUFFIX #{format} #{uri}";'') # filename-extension for format
          storage = fsPath                                            # storage location
          storage += formatExt unless extension == formatExt
          storage.R.writeFile body                                    # cache body
          reader = RDF::Reader.for content_type: format               # select reader
          reader.new(body,base_uri: self,noRDFa: options[:noRDFa]){|_|# instantiate reader
            (env[:repository] ||= RDF::Repository.new) << _ } if reader # read RDF
          return self if options[:intermediate]                       # intermediate fetch, return w/o HTTP-response
          reader ? saveRDF : (puts "ENORDF #{format} #{uri}")         # cache RDF
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}         # expose upstream metadata to downstream
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin # CORS header
          env[:resp]['Set-Cookie'] = h['set-cookie'] if h['set-cookie'] && allowCookies?
          if static
            env[:resp]['Content-Length'] = body.bytesize.to_s         # size header
            [200, env[:resp], [body]]                                 # upstream doc
          else
            graphResponse                                             # local doc
          end
        end
      end
    rescue Exception => e
      status = e.respond_to?(:io) ? e.io.status[0] : ''
      case status
      when /30[12378]/ # redirect
        dest = e.io.meta['location'].R env
        same_path = (path || '/') == (dest.path || '/')
        same_host = host == dest.host
        scheme_downgrade = scheme == 'https' && dest.scheme == 'http'
        if same_path && same_host && scheme_downgrade
          puts "WARNING HTTPS downgraded to HTTP at #{uri}"
          dest.fetchHTTP options
        else
          [302, {'Location' => dest.uri}, []]
        end
      when /304/ # Not Modified
        R304
      when /404/ # Not Found
        upstreamUI? ? [404, (headers e.io.meta), [e.io.read]] : nodeResponse
      when /300|4(0[13]|10)|50[03]|999/
        [status.to_i, (headers e.io.meta), [e.io.read]]
      else
        raise
      end
    end

    def fixedFormat? format = nil
      return true if upstreamUI? || format.to_s.match?(/dash.xml/)
      return false if (query_values||{}).has_key?('rdf') || env[:transform] || !format || format.match?(/atom|html|rss|xml/i)
      return true
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if localNode?            ## local
        if %w{y year m month d day h hour}.member? parts[0]
          dateDir               # timeline redirect
        elsif path == '/mail'   # inbox redirect
          [302, {'Location' => '/d/*/msg*?sort=date&view=table'}, []]
        else                    # local node
          nodeResponse
        end                    ## remote
      elsif path.match? Req204  # connectivity check
        R204
      elsif path.match? HourDir # cached remote - timeslice
        (path + '*' + host.split('.').-(Webize::Plaintext::BasicSlugs).join('.') + '*').R(env).nodeResponse
      elsif handler = HostGET[host] # host lambda
        Populator[host][self] if Populator[host] && !join('/').R.node.exist?
        handler[self]
      elsif host.match? CDNhost # CDN handler
        (AllowedHosts.has_key?(host) || (query_values||{})['allow'] == ServerKey || allowCDN?) ? fetch : deny
      elsif gunk?               # block handler
        deny
      else
        fetch                   # remote node
      end
    end

    alias_method :get, :fetch

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # return header
    end

    # headers formatted and filtered
    def headers raw = nil
      raw ||= env || {} # raw headers
      head = {}         # clean headers
      raw.map{|k,v|     # inspect headers
        k = k.to_s
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix, tokenize
          if %w{cl dfe id spf utc xsrf}.member? t # acronym?
            t = t.upcase                          # upcase
          else
            t[0] = t[0].upcase                    # capitalize
          end
          t                                       # token
        }.join(k.match?(/(_AP_|PASS_SFP)/i) ? '_' : '-') # join tokens
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless Internal_Headers.member?(key.downcase)} # output value

      # Cookies / Referer / User-Agent
      unless allowCookies?
        head.delete 'Cookie'
        head.delete 'Set-Cookie'
        head.delete 'Referer'
      end
      case host
      when /wsj\.com$/
        head['Referer'] = 'http://drudgereport.com/' # thanks, Matt
      when /youtube.com$/
        head['Referer'] = 'https://www.youtube.com/' # make 3rd-party embeds work
      end
      head['User-Agent'] = 'curl/7.65.1' if host == 'po.st' # we want redirection in HTTP HEAD-Location not Javascript
      head.delete 'User-Agent' if host == 't.co'            # so advertise a 'dumb' user-agent

      HTTP.print_header head if ENV.has_key? 'VERBOSE'
      head
    end

    def notfound; [404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def offline?
      ENV.has_key?('OFFLINE') || (query_values||{}).has_key?('OL')
    end

    def OPTIONS
      if AllowedHosts.has_key?(host) || POSThost.match?(host)
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
      r = HTTParty.options uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    def self.Populate host, lambda
      Populator[host] = lambda
    end

    def self.POST host, lambda
      HostPOST[host] = lambda
    end

    def POST
      if handler = HostPOST[host]
        handler[self]
      elsif AllowedHosts.has_key?(host) || POSThost.match?(host)
        self.POSTthru
      else
        denyPOST
      end
    end

    def POSTthru
      r = HTTParty.post uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    def HTTP.print_body head, body
      type = head['Content-Type'] || head['content-type']
      puts type
      puts case type
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
      header.map{|k, v|
        print "\n", [k, v.to_s].join("\t"), ' '}
      print "\n", '_' * 80, ' '
    end

    def PUT
      if AllowedHosts.has_key? host
        self.PUTthru
      else
        env[:deny] = true
        [204, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => 'authorization, content-type, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-hostname, x-lib-version, x-locale, x-requested-with',
               'Access-Control-Allow-Origin' => allowedOrigin},
         []]
      end
    end

    def PUTthru
      r = HTTParty.put uri, headers: headers, body: env['rack.input'].read
      [r.code, (headers r.headers), [r.body]]
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' if !h || h.empty?
      '?' + h.map{|k,v|
        puts "WARNING query key #{k} has multiple vals: #{v.join ' '}, using #{v[0]}" if v.class == Array && v.size > 1
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def selectFormat default = 'text/html'
      return default unless env && env.has_key?('HTTP_ACCEPT') # default via no specification

      index = {} # q -> format map
      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats selected in descending q-value order
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with 🐢-preference
          return default if f == '*/*'                        # default via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF via writer definition
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF via writer definition

      default                                                 # default
    end

    def upstreamUI; env[:UX] = true; self end

    def upstreamUI?
      env.has_key?(:UX) ||                          # request environment
        ENV.has_key?('UX') ||                       # process environment
        parts.member?('embed') ||                   # embed URL
        UIhosts.member?(host) ||                    # UI host
        query_values&.has_key?('UX')                # request argument
    end

  end
  include HTTP
end
