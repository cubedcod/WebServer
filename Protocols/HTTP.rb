# coding: utf-8
%w(brotli cgi digest/sha2 httparty open-uri rack).map{|_| require _}

class WebResource
  module HTTP
    include URIs

    HostGET = {}
    Methods = %w(GET HEAD OPTIONS POST PUT)
    Args = %w(notransform offline order sort view)

    def allow_domain?
      c = AllowDomains                                              # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

    def cacheResponse
      nodes = nodeSet             # find local nodes
      if nodes.size == 1 && (nodes[0].static_node? || # single node found in client-preferred or fixed format
                            (nodes[0].named_format == selectFormat && (env[:notransform] || nodes[0].named_format != 'text/html')))
        nodes[0].fileResponse     # static response on file, return
      else
        nodes.map{|_|_.🐢.loadRDF}# transcode to RDF if needed, load RDF
        saveRDF if env[:updates]  # cache resources emitted in RDF transcode
        graphResponse             # graph response
      end
    end

    def self.call env
      return [405,{},[]] unless Methods.member? env['REQUEST_METHOD']      # method
      uri = RDF::URI('//' + env['HTTP_HOST']).                             # host
              join(env['REQUEST_PATH'].gsub /\/\/+/, '/').R env            # path
      uri.scheme = uri.local_node? ? 'http' : 'https'                      # scheme
      if env['QUERY_STRING'] && !env['QUERY_STRING'].empty?                # query
        uri.query = env['QUERY_STRING'].sub(/^&/,'').gsub(/&&+/,'&')       # strip leading + consecutive &s so URI library doesn't freak out
        qs = uri.query_values                                              # parse query args
        Args.map{|k|env[k.to_sym] = qs.delete(k) || true if qs.has_key? k} # read local (client <> proxy) args
        qs.empty? ? (uri.query = nil) : (uri.query_values = qs)            # set remote (proxy <> origin) args
      end
      env.update({base: uri, feeds: [], links: {}, log: [], resp: {}})     # response environment
      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body|      # dispatch request
        format = uri.format_icon head['Content-Type']                      # logger
        color = env[:deny] ? '31;1' : (format_color format)
        puts [env[:deny] ? '🛑' : (action_icon env['REQUEST_METHOD'], env[:fetched]), (status_icon status), format, env[:repository] ? (env[:repository].size.to_s + '⋮') : nil,
              env['HTTP_REFERER'] ? ["\e[#{color}m", env['HTTP_REFERER'], "\e[0m→"] : nil, "\e[#{color}#{env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m",
              env[:base], "\e[0m", head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil, Verbose ? [env['HTTP_ACCEPT'], head['Content-Type']].compact.join(' → ') : nil, env[:log]
             ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '
        [status, head, body]}                                              # response
    rescue Exception => e                                                  # error handler
      msg = [[uri, e.class, e.message].join(' '), e.backtrace].join "\n"
      puts "\e[7;31m500\e[0m " + msg if Verbose
      [500, {'Content-Type' => 'text/html; charset=utf-8'}, env['REQUEST_METHOD'] == 'HEAD' ? [] : ["<!DOCTYPE html>\n<html><body class='error'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri.uri_toolbar]}<pre><a href='#{uri.remoteURL}' >500</a>\n#{CGI.escapeHTML msg}</pre></body></html>"]]
    end

    def client_etags
      if tags = env['HTTP_IF_NONE_MATCH']
        tags.strip.split /\s*,\s*/
      else
        []
      end
    end

    def HTTP.decompress head, body
      encoding = head.delete 'Content-Encoding'
      return body unless encoding
      case encoding.to_s
      when /^br(otli)?$/i
        Brotli.inflate body
      when /gzip/i
        (Zlib::GzipReader.new StringIO.new body).read
      when /flate|zip/i
        Zlib::Inflate.inflate body
      else
        puts "undefined Content-Encoding: #{encoding}"
        head['Content-Encoding'] = encoding
        body
      end
    rescue Exception => e
      puts [e.class, e.message].join " "
      head['Content-Encoding'] = encoding
      body
    end
 
    def deny status = 200, type = nil
      env[:deny] = true
      type, content = if type == :stylesheet || ext == 'css'
                        ['text/css', '']
                      elsif type == :font || %w(eot otf ttf woff woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(bmp gif png).member?(ext)
                        ['image/png', SiteIcon]
                      elsif type == :script || ext == 'js'
                        ['application/javascript', "// URI: #{uri.match(Gunk) || host}"]
                      elsif type == :JSON || ext == 'json'
                        ['application/json','{}']
                      else
                        url = (query&.match? /utm[^a-z]/) ? path : uri
                        ['text/html; charset=utf-8',
                         "<html><body class='blocked'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri_toolbar]}<a class='unblock' href='#{url}'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => origin,
        'Content-Type' => type},
       [content]]
    end

    def deny?
      return true  if uri.match? Gunk # URI filter
      return false if !host || HostGET.has_key?(host)
      return false if allow_domain?   # DNS filters
      return true  if deny_domain?
             false
    end

    def deny_domain?
      c = DenyDomains                                               # init cursor
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf in domain tree
    end

    def env e = nil
      if e
        @env = e;  self
      else
        @env ||= {}
      end
    end

    # fetch from cache or remote
    def fetch
      return cacheResponse if offline?
      return [304,{},[]] if (env.has_key?('HTTP_IF_NONE_MATCH') || env.has_key?('HTTP_IF_MODIFIED_SINCE')) && static_node? # client has static node cached
      nodes = nodeSet
      return nodes[0].fileResponse if nodes.size == 1 && nodes[0].static_node?                            # server has static node cached
      fetchHTTP                                                                 # fetch via HTTPS
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      ['http://', host, ![nil, 443].member?(port) ? [':', port] : nil, path, query ? ['?', query] : nil].join.R(env).fetchHTTP rescue notfound # fetch via HTTP
    end

    # fetch remote data to local graph
    def fetchHTTP thru: true                                          # return HTTP response to caller?
      URI.open(uri, headers.merge({redirect: false})) do |response|
        env[:fetched] = true                                          # mark as a network-fetch for logger
        h = headers response.meta                                     # response headers
        case response.status[0].to_i
        when 204                                                      # no content
          [204, {}, []]
        when 206                                                      # partial content
          h['Access-Control-Allow-Origin'] ||= origin
          [206, h, [response.read]]                                   # return part
        else                                                          # full content
          body = HTTP.decompress h, response.read                     # decompress content
          format = if path=='/feed'||(query_values||{})['mime']=='xml'# format fixed at feed-URL (override erroneous upstream text/html)
                     'application/atom+xml'
                   elsif content_type = h['Content-Type']             # format defined in HTTP header
                     ct = content_type.split(/;/)
                     if ct.size == 2                                  # charset defined in HTTP header
                       charset = ct[1].sub(/.*charset=/i,'')
                       charset = nil if charset.empty? || charset == 'empty'
                     end
                     ct[0]
                   elsif named_format                                 # format via name-extension map
                     named_format
                   end
          if format                                                   # format defined
            if !charset && format.index('html') && metatag = body[0..4096].encode('UTF-8', undef: :replace, invalid: :replace).match(/<meta[^>]+charset=['"]?([^'">]+)/i)
              charset = metatag[1]                                    # charset defined in <head>
            end
            if charset
              charset = 'UTF-8' if charset.match? /utf.?8/i           # normalize UTF-8 charset-id
              charset = 'Shift_JIS' if charset.match? /s(hift)?.?jis/i# normalize Shift-JIS charset-id
            end                                                       # encode text in UTF-8
            body.encode! 'UTF-8', charset, invalid: :replace, undef: :replace if format.match? /(ht|x)ml|script|text/
            body = Webize.clean self, body, format                    # clean data
            if formatExt = Suffixes[format] || Suffixes_Rack[format]  # look up format-suffix
              file = fsPath                                           # cache base path
              file += '/index' if file[-1] == '/'                     # append directory-data slug
              file += formatExt unless File.extname(file)==formatExt  # append format-suffix
              FileUtils.mkdir_p File.dirname file                     # create parent directories
              File.open(file, 'w'){|f| f << body }                    # cache fetched data
            else
              puts "extension undefined for #{format}"                # warning: undefined format-suffix
            end
            if reader = RDF::Reader.for(content_type: format)         # reader defined for format?
              env[:repository] ||= RDF::Repository.new                # initialize RDF repository
              if format.index('text') && timestamp=h['Last-Modified'] # HTTP metadata to RDF-graph
                env[:repository] << RDF::Statement.new(self, Date.R, Time.httpdate(timestamp.gsub('-',' ').sub(/((ne|r)?s|ur)?day/,'')).iso8601) rescue nil
              end
              reader.new(body, base_uri: self, path: file){|g|env[:repository] << g} # read RDF
            else
              puts "RDF::Reader undefined for #{format}"              # warning: undefined Reader
            end unless format.match? /octet-stream|script|vnd/
          else
            puts "ERROR format undefined on #{uri}"                   # warning: undefined format
          end
          return unless thru                                          # skip HTTP response
          saveRDF                                                     # cache graph-data
          env[:resp]['Access-Control-Allow-Origin'] ||= origin        # CORS header
          h['Link'] && h['Link'].split(',').map{|link|                # Link headers
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}                                                      # upstream headers
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type).map{|k|env[:resp][k] ||= h[k] if h[k]}
          env[:resp]['Content-Length'] = body.bytesize.to_s           # Content-Length header
          env[:resp]['ETag'] ||= h['Etag']                            # ETag header
          if env[:notransform] || !format || format.match?(/css|script/) || !format.match?(/json|text|xml/) # fixed format?
            [200, env[:resp], [body]]                                 # data in original format
          else                                                        # content-negotiated transform allowed
            if format.index 'json'                                    # upstream data is JSON
              if (selectFormat format) == format                      # JSON preferred?
                [200, env[:resp], [body]]                             # JSON in original format
              else
                graphResponse format                                  # transform JSON to requested format
              end
            else                                                      # upstream Atom/HTML/RSS/XML/TXT
              graphResponse format                                    # transform to requested format, or within-MIME reformat
            end
          end
        end
      end
    rescue Exception => e
      status = e.respond_to?(:io) ? e.io.status[0] : ''
      case status
      when /30[12378]/ # redirect
        dest = (join e.io.meta['location']).R env
        if scheme == 'https' && dest.scheme == 'http'
          puts "WARNING HTTPS downgraded to HTTP: #{uri} -> #{dest}"
          dest.fetchHTTP
        else
          [302, {'Location' => dest.href}, []]
        end
      when /304/ # Not Modified
        [304, {}, []]
      when /300|[45]\d\d/ # Not Found, Not Allowed or general upstream error
        env[:status] = status.to_i
        head = headers e.io.meta
        body = HTTP.decompress head, e.io.read
        if head['Content-Type']&.index 'html'
          body = Webize::HTML.clean body, self
          env[:repository] ||= RDF::Repository.new
          RDF::Reader.for(content_type: 'text/html').new(body, base_uri: self){|g|env[:repository] << g} # read RDF
        end
        head['Content-Length'] = body.bytesize.to_s
        env[:notransform] ? [env[:status], head, [body]] : env[:base].cacheResponse
      else
        raise
      end
    end

    def fileResponse
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      return [304,{},[]] if client_etags.include? env[:resp]['ETag']    # client has file
      Rack::Files.new('.').serving(Rack::Request.new(env), fsPath).yield_self{|s,h,b|
        if 304 == s
          [304, {}, []]                                                 # unmodified file
        else
          if h['Content-Type'] == 'application/javascript'
            h['Content-Type'] = 'application/javascript; charset=utf-8' # add charset 
          elsif !h.has_key?('Content-Type')                             # format missing?
            if mime = Rack::Mime::MIME_TYPES[extension]                 # format via Rack extension-map
              h['Content-Type'] = mime
            elsif RDF::Format.file_extensions.has_key? ext.to_sym       # format via RDF extension-map
              h['Content-Type'] = RDF::Format.file_extensions[ext.to_sym][0].content_type[0]
            end
          end
          env[:resp]['Access-Control-Allow-Origin'] ||= origin
          env[:resp]['Content-Length'] = node.size.to_s
          [s, h.update(env[:resp]), b]                                  # file response
        end}
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local_node?
        p = parts[0]
        if !p
          [302, {'Location' => '/h'}, []]
        elsif %w{m d h}.member? p              # goto current day/hour/min-dir
          dateDir
        elsif path == '/favicon.ico'
          [200, {'Content-Type' => 'image/png'}, [SiteIcon]]
        elsif path == '/log' || path == '/log/'
          log_search                           # search log
        elsif path == '/mail'
          [302,{'Location' => '/d?f=msg*'},[]] # goto "inbox" of today's messages
        elsif !p.match? /[.:]/                 # no hostname/scheme characters in first path-segment
          timeMeta                             # reference temporally-adjacent nodes in metadata
          cacheResponse                        # local path
        else                                   # hostname in first path-segment
          (env[:base] = remoteURL).hostHandler # host handler (mapped to local URI-space)
        end
      else
        hostHandler                            # host handler
      end
    end

    def graphResponse defaultFormat='text/html'
      return notfound if !env.has_key?(:repository) || env[:repository].empty? # empty graph
      return [304,{},[]] if client_etags.include? env[:resp]['ETag']           # client has file
      format = selectFormat defaultFormat                                      # response format
      env[:resp]['Access-Control-Allow-Origin'] ||= origin                     # response headers
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      body = case format                                                       # response body
             when /html/
               htmlDocument                                                    # serialize HTML
             when /atom|rss|xml/
               feedDocument                                                    # serialize Atom/RSS
             else                                                              # serialize RDF
               if writer = RDF::Writer.for(content_type: format)
                 env[:repository].dump writer.to_sym, base_uri: self
               else
                 puts "no Writer for #{format}!"
                 ''
               end
             end
      env[:resp]['Content-Length'] = body.bytesize.to_s                        # response size
      [env[:status] || 200, env[:resp], [body]]                                # graph response
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # return status and header
    end

    # client<>proxy headers not repeated on proxy<>origin connections
    SingleHopHeaders = %w(base colors connection downloadable feeds fetched graph host images keep-alive links log notransform offline order path-info query-string
 remote-addr repository request-method request-path request-uri resp script-name server-name server-port server-protocol server-software sort status
 te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via view x-forwarded-for)

    # headers case-normalized
    def headers raw = nil
      raw ||= env || {}        # raw headers
      head = {}                # clean headers
      raw.map{|k,v|            # inspect (k,v) pairs
        k = k.to_s                                                # stringify key
        unless k.index('rack.') == 0                              # strip Rack-internal headers
          key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip Rack HTTP_ prefix and tokenize
            if %w{cf cl csrf ct dfe dnt id spf utc xss xsrf}.member? t # acronyms
              t = t.upcase       # upcase acronym
            else
              t[0] = t[0].upcase # capitalize token
            end
            t}.join '-'          # join tokens
          head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless SingleHopHeaders.member? key.downcase
        end} # set header at normalized key

      #head['Accept'] = ['text/turtle', head['Accept']].join ',' unless (head['Accept']||'').match?(/text\/turtle/) # accept Turtle even if requesting client doesnt
      head['Referer'] = 'http://drudgereport.com/' if host.match? /wsj\.com$/
      head['Referer'] = 'https://' + host + '/' if %w(gif jpeg jpg png svg webp).member?(ext.downcase) || parts.member?('embed')
      head['User-Agent'] = if %w(po.st t.co).member? host # we want shortlink-expansion via HTTP-redirect, not Javascript, so advertise a basic user-agent
                             'curl/7.65.1'
                           else
                             'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36'
                           end
      head
    end

    def hostHandler
      qs = query_values || {}
      cookie = join('/cookie').R
      cookie.writeFile qs['cookie'] if qs['cookie'] && !qs['cookie'].empty? # cache cookie
      env['HTTP_COOKIE'] = cookie.readFile if cookie.node.exist? # fetch cookie from jar
      if path == '/favicon.ico' && node.exist?
        fileResponse
      elsif qs['download'] == 'audio'
        slug = qs['list'] || qs['v'] || 'audio'
        storageURI = join([basename, slug].join '.').R
        storage = storageURI.fsPath
        unless File.directory? storage
          FileUtils.mkdir_p storage
          pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{uri}\""
          Process.detach pid
        end
        [302, {'Location' => storageURI.href + '?offline'}, []]
      elsif handler = HostGET[host] # host lambda
        handler[self]
      elsif deny?
        deny
      elsif parts[-1]&.match? /^gen(erate)?_?204$/
        [204, {}, []]
      else                       # remote graph-node
        fetch
      end
    end

    def log_search
      env.update({sort: sizeAttr = '#size', view: 'table'})
      results = {}
      if q = (query_values||{})['q']
        `grep --text -i #{Shellwords.escape 'http.*' + q} web.log | tr -s ' ' | cut -d ' ' -f 7 `.each_line{|uri|
          u = uri.R
          results[uri] ||=  {'uri' => uri,
                             sizeAttr => 0,
                             Title => [[u.host, u.path, (u.query ? ['?', u.query] : nil)].join]}
          results[uri][sizeAttr] += 1}
      end
      [200, {'Content-Type' => 'text/html'}, [(htmlDocument results)]]
    end

    def notfound; [env[:status] || 404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def offline?
      ENV.has_key?('OFFLINE') || env.has_key?(:offline)
    end

    def origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' if !h || h.empty?
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def OPTIONS
      if allow_domain? && !uri.match?(Gunk)                 # POST allowed?
        head = headers                                      # read head
        body = env['rack.input'].read                       # read body
        env.delete 'rack.input'

        if Verbose                                          # log request
          puts 'OPTIONS ' + uri
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '>>>>>>>>', body
        end

        r = HTTParty.options uri, headers: head, body: body    # OPTIONS request to origin
        head = headers r.headers                            # response headers
        body = r.body

        if Verbose                                          # log response
          puts '-' * 40
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '<<<<<<<<', body unless head['Content-Encoding']
        end

        [r.code, head, [body]]                              # response
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Headers' => AllowedHeaders,
               'Access-Control-Allow-Origin' => origin}, []]
      end
    end

    def POST
      if allow_domain? && !uri.match?(Gunk)                 # POST allowed?
        head = headers                                      # read head
        body = env['rack.input'].read                       # read body
        env.delete 'rack.input'

        if Verbose                                          # log request
          puts 'POST ' + uri
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '>>>>>>>>', body
        end

        r = HTTParty.post uri, headers: head, body: body    # POST to origin
        head = headers r.headers                            # response headers
        body = r.body

        if format = head['Content-Type']                    # response format
          if reader = RDF::Reader.for(content_type: format) # reader defined for format?
            env[:repository] ||= RDF::Repository.new        # initialize RDF repository
            reader.new(HTTP.decompress({'Content-Encoding' => head['Content-Encoding']}, body), base_uri: self){|g|
              env[:repository] << g}                        # read RDF
            saveRDF                                         # cache RDF
          else
            puts "RDF::Reader undefined for #{format}"      # Reader undefined
          end
        end

        if Verbose                                          # log response
          puts '-' * 40
          head.map{|k,v| puts [k,v.to_s].join "\t" }
          puts '<<<<<<<<', body unless head['Content-Encoding']
        end

        [r.code, head, [body]]                              # response
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Origin' => origin}, []]
      end
    end


    def remoteURL
      ['https:/' , path.sub(/^\/https?:\/+/, '/'),
       (query ? ['?', query] : nil),
       (fragment ? ['#', fragment] : nil) ].join.R env
    end

    def selectFormat default='text/html'
      return default unless env.has_key? 'HTTP_ACCEPT' # no preference specified
      index = {} # (q-value -> format) table

      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats grouped on descending q-value
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with 🐢-winner
          return default if f == '*/*'                        # wildcard, select default
          return f if RDF::Writer.for(:content_type => f) ||  # highest q w/ RDF writer defined
            ['application/atom+xml','text/html'].member?(f)}} # highest q w/ nonRDF writer defined

      default                                                 # default
    end

  end
  include HTTP
end
