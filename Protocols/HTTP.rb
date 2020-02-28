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
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Populator = {}
    ServerKey = Digest::SHA2.hexdigest([`uname -a`, (Pathname.new __FILE__).stat.mtime].join)[0..7]
    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert
    SingleHop = %w(connection fetch gunk host keep-alive links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rack.tempfiles rdf refhost remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software site-chrome summary sort te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests ux version via x-forwarded-for)

    def self.Allow host
      AllowedHosts[host] = true
    end

    def allowCookies?
      @cookies || AllowedHosts.has_key?(host) || CookieHosts.has_key?(host) || CookieHost.match?(host)
    end

    def allowCDN?
      (CacheFormats - %w(gif html js)).member?(ext.downcase) && !path.match?(Gunk)
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
      uri.query = env['QUERY_STRING'].sub(/^&/,'') if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?
      resource = uri.R env                                                      # instantiate web resource
      env[:refhost] = env['HTTP_REFERER'].R.host if env.has_key? 'HTTP_REFERER' # referring host
      env[:resp] = {}                                                           # response-header storage
      env[:links] = {}                                                          # response-header links
      resource.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch
        ext = resource.path ? resource.ext.downcase : ''                        # log
        mime = head['Content-Type'] || ''

        action_icon = case env['REQUEST_METHOD']
                      when 'OPTIONS'
                        '🔧'
                      when 'POST'
                        '📝'
                      when 'GET'
                        env[:fetch] ? '🐕' : nil
                      else
                        env['REQUEST_METHOD']
                      end

        status_icon = env[:deny] && '🛑' || {204 => '🌐', 301 => '➡️', 302 => '➡️', 303 => '➡️', 304 => '✅', 401 => '🚫', 403 => '🚫', 404 => '❓', 410 => '❌', 500 => '🚩'}[status] || (status == 200 ? nil : status)

        format_icon = if ext == 'css' || mime.match?(/text\/css/)
                        '🎨'
                      elsif ext == 'js' || mime.match?(/script/)
                        '📜'
                      elsif ext == 'json' || mime.match?(/json/)
                        '🗒'
                      elsif %w(gif jpeg jpg png svg webp).member?(ext) || mime.match?(/^image/)
                        '🖼️'
                      elsif %w(aac flac m4a mp3 ogg opus).member?(ext) || mime.match?(/^audio/)
                        '🔉'
                      elsif %w(mp4 webm).member?(ext) || mime.match?(/^video/)
                        '🎬'
                      elsif ext == 'ttl' || mime.match?(/text\/turtle/)
                        '🐢'
                      elsif %w(htm html).member?(ext) || mime.match?(/html/)
                        '📃'
                      else
                        mime
                      end

        color = if env[:deny]
                  '31;7;1'
                else
                  case format_icon
                  when '🖼️'
                    '33;1'
                  when '📜'
                    '36;1'
                  when '🐢'
                    32
                  else
                    7
                  end
                end

        triple_count = env[:repository] ? (env[:repository].size.to_s + '⋮') : nil

        if [204, 304].member? status
        elsif [301, 302, 303].member? status # redirect
          puts ["\e[36m", resource.uri, status_icon + ' ', head['Location'], "\e[0m"].join ' '
        else
          puts [action_icon, status_icon, format_icon, triple_count, env[:refhost] ? ["\e[#{color};7m", env[:refhost], "\e[0m→"] : nil, "\e[#{color}m", resource.uri, "\e[0m"].compact.join ' '
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

    def cookies
      cookie = (hostPath + '.cookie').R
      if jar = cookie.readFile              # jar cookie. invalidate on your own, see Twitter example
        env['HTTP_COOKIE'] = jar unless env['HTTP_COOKIE'] == jar
      elsif env.has_key?('HTTP_COOKIE') && allowCookies?
        puts '🍪 ' + env['HTTP_COOKIE']
        cookie.writeFile env['HTTP_COOKIE'] # put cookie in jar
      end
      self
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
      return [301, {'Location' => path}, []] if !(query_values||{}).keys.grep(/^utm/).empty?
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
      [202, {'Access-Control-Allow-Credentials' => 'true',
             'Access-Control-Allow-Origin' => allowedOrigin}, []]
    end

    def env e = nil
      if e
        @env = e
        self
      else
        @env #||= {}
      end
    end

    # fetch node from cache or remote server
    def fetch options=nil
      return nodeResponse if ENV.has_key? 'OFFLINE'                                               # offline-only response
      if StaticFormats.member? ext.downcase                                                       # static-cache formats:
        return [304, {}, []] if env.has_key?('HTTP_IF_NONE_MATCH')||env.has_key?('HTTP_IF_MODIFIED_SINCE') # client-cached node
        return fileResponse if node.file?                                                         # server-cached node (direct hit)
      end
      c = nodeSet ; return c[0].fileResponse if c.size == 1 && StaticFormats.member?(c[0].ext)    # server-cached node (indirect hit)

      # cache miss, network fetch

      options ||= {}
      location = ['//', host, (port ? [':', port] : nil), path, options[:suffix], (query ? ['?', query] : nil)].join
      primary  = ('https:' + location).R env
      fallback = ('http:' + location).R env

      env[:fetch] = true
      primary.fetchHTTP options
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      fallback.fetchHTTP options
    end

    def fetchHTTP options = {}
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
                     RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
                   end
          static = !options[:reformat] && (fixedFormat? format)       # rewritable format?
          body = Webize::HTML.degunk body, static if format == 'text/html' && !AllowedHosts.has_key?(host) # clean HTML
          formatExt = Suffixes[format] || Suffixes_Rack[format] || (puts "ENOSUFFIX #{format} #{uri}";'') # filename-extension for format
          storage = fsPath                                            # storage location
          storage += formatExt unless extension == formatExt
          storage.R.writeFile body                                    # cache body
          reader = RDF::Reader.for content_type: format               # select reader
          reader.new(body, base_uri: self){|_|                        # read RDF
            (env[:repository] ||= RDF::Repository.new) << _ } if reader && !%w(.css .gif .ico .jpg .js .png .svg).member?(formatExt)
          return self if options[:intermediate]                       # intermediate fetch, return w/o HTTP response
          reader ? saveRDF : (puts "ENORDF #{format} #{uri}")         # cache RDF
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}         # expose upstream metadata to downstream
          env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin # CORS header
          env[:resp]['Set-Cookie'] ||= h['set-cookie'] if h['set-cookie'] && allowCookies?
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
        [304, {}, []]
      when /404/ # Not Found
        upstreamUI? ? [404, (headers e.io.meta), [e.io.read]] : nodeResponse
      when /300|4(0[13]|10|29)|50[03]|999/
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
      cookies
      if query_values&.has_key? 'fullContent'
        env[:links][:up] = '?'
      elsif path != '/'
        up = File.dirname path
        up += '/' unless up == '/'
        up += '?' + query if query
        env[:links][:up] = up
      end

      if localNode?            ## local
        if %w{y year m month d day h hour}.member? parts[0]
          dateDir               # timeline redirect
        elsif path == '/mail'   # inbox redirect
          [302, {'Location' => '/d/*/msg*?sort=date&view=table'}, []]
        else                    # local node
          nodeResponse
        end                    ## remote
      elsif path.match? /gen(erate)?_?204$/ # connectivity check
        [204, {}, []]
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
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHop.member?(key.downcase)} # output value

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

      head
    end

    def notfound; [404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

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
      head = headers
      body = env['rack.input'].read
      env.delete 'rack.input'
      print_header head if ENV.has_key? 'VERBOSE'
      r = HTTParty.post uri, headers: head, body: body
      head = headers r.headers
      print_header head if ENV.has_key? 'VERBOSE'
      [r.code, head, [r.body]]
    end

    def print_body head, body
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

    def print_header header
      print "\n🔗 " + uri
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
