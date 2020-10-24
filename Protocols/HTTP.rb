# coding: utf-8
%w(brotli cgi digest/sha2 open-uri rack).map{|_| require _}
class WebResource
  module HTTP
    include URIs

    HostGET = {}

    def allowed_origin
      if env['HTTP_ORIGIN']
        env['HTTP_ORIGIN']
      elsif referer = env['HTTP_REFERER']
        'http' + (host == 'localhost' ? '' : 's') + '://' + referer.R.host
      else
        '*'
      end
    end

    def cacheResponse
      nodes = nodeSet            # find local nodes
      if nodes.size == 1 && (nodes[0].static_node? || # one node and it's nontransformable or in the preferred-via-conneg format
                            (nodes[0].named_format == selectFormat && (no_transform? || nodes[0].named_format != 'text/html')))
        nodes[0].fileResponse    # static response on file
      else                       # load graph
        nodes.map{|n|
          env[:summary] ? n.summary : n.🐢}.map &:loadRDF # load RDF
        saveRDF if env[:updates] # cache new resources found during RDF-ization
        graphResponse            # graph response
      end
    end

    def self.call env
      return [405,{},[]] unless %w(GET HEAD POST).member? env['REQUEST_METHOD'] # permit HTTP methods
      uri = RDF::URI('//' + env['HTTP_HOST']).join(env['REQUEST_PATH']).R env # URI
      uri.scheme = uri.local_node? ? 'http' : 'https'                         # scheme
      uri.query = env['QUERY_STRING'].sub(/^&/,'').gsub(/&&+/,'&') if env['QUERY_STRING'] && !env['QUERY_STRING'].empty? # strip leading + consecutive & from qs so URI library doesn't freak out
      env.update({base: uri, feeds: [], links: {}, resp: {}})                 # environment

      uri.send(env['REQUEST_METHOD']).yield_self{|status, head, body| # dispatch request
        format = uri.format_icon head['Content-Type']                 # log response
        color = env[:deny] ? '31;1' : (format_color format)
        puts [env[:deny] ? '🛑' : (action_icon env['REQUEST_METHOD'], env[:fetched]), (status_icon status), format,
              env[:repository] ? (env[:repository].size.to_s + '⋮') : nil,
              env['HTTP_REFERER'] ? ["\e[#{color}m", env['HTTP_REFERER'], "\e[0m→"] : nil,
              "\e[#{color}#{env['HTTP_REFERER'] && !env['HTTP_REFERER'].index(env[:base].host) && ';7' || ''}m",
              env[:base], "\e[0m", head['Location'] ? ["→\e[#{color}m", head['Location'], "\e[0m"] : nil,
              [env['HTTP_ACCEPT'], head['Content-Type']].compact.join(' → ')
             ].flatten.compact.map{|t|t.to_s.encode 'UTF-8'}.join ' '

        [status, head, body]} # response

    rescue Exception => e
      msg = [[uri, e.class, e.message].join(' '), e.backtrace].join "\n"
      puts "\e[7;31m500\e[0m " + msg
      [500, {'Content-Type' => 'text/html; charset=utf-8'}, env['REQUEST_METHOD'] == 'HEAD' ? [] : ["<!DOCTYPE html>\n<html><body class='error'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri.uri_toolbar]}<pre><a href='#{uri.remoteURL}' >500</a>\n#{CGI.escapeHTML msg}</pre></body></html>"]]
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
 
    def deny status = 200, type = nil
      return [302, {'Location' => ['//', host, path].join.R(env).href}, []] if query&.match? Gunk # strip query
      env[:deny] = true
      type, content = if type == :stylesheet || ext == 'css'
                        ['text/css', '']
                      elsif type == :font || %w(eot otf ttf woff woff2).member?(ext)
                        ['font/woff2', SiteFont]
                      elsif type == :image || %w(bmp gif png).member?(ext)
                        ['image/png', SiteIcon]
                      elsif type == :script || ext == 'js'
                        ['application/javascript', '//']
                      elsif type == :JSON || ext == 'json'
                        ['application/json','{}']
                      else
                        ['text/html; charset=utf-8',
                         "<html><body class='blocked'>#{HTML.render [{_: :style, c: SiteCSS}, {_: :script, c: SiteJS}, uri_toolbar]}<a class='unblock' href='#{uri}'>⌘</a></body></html>"]
                      end
      [status,
       {'Access-Control-Allow-Credentials' => 'true',
        'Access-Control-Allow-Origin' => allowed_origin,
        'Content-Type' => type},
       [content]]
    end

    # if needed, generate and return entity. delegated to Rack handler if file reference
    def entity generator = nil
      if env['HTTP_IF_NONE_MATCH']&.strip&.split(/\s*,\s*/)&.include? env[:resp]['ETag']
        [304, {}, []]                            # unmodified entity
      else
        body = generator ? generator.call : self # generate entity
        if body.class == WebResource             # file-reference?
          Rack::Files.new('.').serving(Rack::Request.new(env), body.fsPath).yield_self{|s,h,b|
            if 304 == s
              [304, {}, []]                      # unmodified file
            else
              if h['Content-Type'] == 'application/javascript'
                h['Content-Type'] = 'application/javascript; charset=utf-8' # add charset tag
              elsif RDF::Format.file_extensions.has_key? body.ext.to_sym # format via path extension
                h['Content-Type'] = RDF::Format.file_extensions[body.ext.to_sym][0].content_type[0]
              end
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]       # file
            end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [200, env[:resp], [body]]              # inline data
        end
      end
    end

    def env e = nil
      if e
        @env = e;  self
      else
        @env ||= {}
      end
    end

    # fetch from cache or remote server
    def fetch
      return cacheResponse if offline?
      return [304,{},[]] if (env.has_key?('HTTP_IF_NONE_MATCH') || env.has_key?('HTTP_IF_MODIFIED_SINCE')) && static_node? # client has static node cached
      nodes = nodeSet; return nodes[0].fileResponse if nodes.size == 1 && nodes[0].static_node?                            # server has static node cached
      fetchHTTP                                                                 # fetch via HTTPS
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenURI::HTTPError, OpenSSL::SSL::SSLError, RuntimeError, SocketError
      ['http://', host, path, query ? ['?', query] : nil].join.R(env).fetchHTTP # fetch via HTTP
    end

    # fetch from remote                            options:
    def fetchHTTP thru: true,                        # pass HTTP response to caller
                  transformable: !no_transform?      # allow transforms: format conversions and same-format (HTML reformat, code pretty-print) rewrites
      URI.open(uri, headers.merge({redirect: false})) do |response| ; env[:fetched] = true
        h = response.meta                            # upstream metadata
        if response.status.to_s.match? /206/         # partial response
          h['Access-Control-Allow-Origin'] = allowed_origin unless h['Access-Control-Allow-Origin'] || h['access-control-allow-origin']
          [206, h, [response.read]]                  # return part
        else
          format = if path == '/feed' || (query_values||{})['mime'] == 'xml'
                     'application/atom+xml'          # Atom/RSS content-type via URL
                   elsif h.has_key? 'content-type'
                     h['content-type'].split(/;/)[0] # content-type in HTTP metadata
                   elsif named_format                # content-type in name extension
                     named_format
                   end
          body = HTTP.decompress h, response.read    # read body
          if format
            if reader = RDF::Reader.for(content_type: format) # reader defined for format
              env[:repository] ||= RDF::Repository.new                # init RDF repository
              if timestamp = h['Last-Modified'] || h['last-modified'] # add HTTP metadata to graph
                env[:repository] << RDF::Statement.new(self, Date.R, Time.httpdate(timestamp.gsub('-',' ').sub(/((ne|r)?s|ur)?day/,'')).iso8601) rescue nil
              end
              reader.new(body,base_uri: self){|g|env[:repository] << g} # read RDF
            else
              puts "RDF::Reader undefined for #{format}"
            end
          else
            puts "ERROR format unknown for #{uri}"
          end
          return unless thru                                          # fetch to runtime graph only, no HTTP response returned to caller

          # cache fill
          if formatExt = Suffixes[format] || Suffixes_Rack[format]    # lookup format suffix
            if extension == formatExt                                 # suffix match
              cache = self
            else                                                      # suffix incorrect or missing
              cache = uri
              cache += 'index' if uri[-1] == '/'                      # append directory-index slug
              cache += formatExt                                      # append format-suffix
              cache = cache.R                                         # cache pointer
            end
            cache.writeFile body if cache.static_node?                # cache upstream entity
          else
            puts "extension undefined for #{format}"                  # notice on undefined extension
          end
          saveRDF                                                     # cache graph-data

          # response metadata
          %w(Access-Control-Allow-Origin Access-Control-Allow-Credentials Content-Type ETag).map{|k|
            env[:resp][k] ||= h[k.downcase] if h[k.downcase]}         # upstream metadata
          env[:resp]['Access-Control-Allow-Origin'] ||= allowed_origin # CORS header
          h['link'] && h['link'].split(',').map{|link|                # parse and merge upstream Link headers to request-environment
            ref, type = link.split(';').map &:strip
            if ref && type
              ref = ref.sub(/^</,'').sub />$/, ''
              type = type.sub(/^rel="?/,'').sub /"$/, ''
              env[:links][type.to_sym] = ref
            end}

          # response
          if transformable && !(format||'').match?(/audio|css|image|octet|script|video/)
            graphResponse                                     # local format
          else
            body = Webize::HTML.cacherefs body, env if format == 'text/html' # resolve cache references
            env[:resp]['Content-Length'] = body.bytesize.to_s # update Content-Length
            [200, env[:resp], [body]]                         # upstream format
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
      when /300|[45]\d\d/ # Not Found/Allowed or upstream error
        env[:origin_status] = status.to_i
        if e.io.meta['content-type']&.match? /text\/html/
          (env[:repository] ||= RDF::Repository.new) << RDF::Statement.new(self, Content.R, Webize::HTML.format(HTTP.decompress(e.io.meta, e.io.read), self)) # upstream message
        end
        cacheResponse
      else
        raise
      end
    end

    def self.GET arg, lambda = NoGunk
      HostGET[arg] = lambda
    end

    def GET
      if local_node?
        p = parts[0]
        if !p
          [302, {'Location' => '/h'}, []]
        elsif %w{m d h}.member? p              # goto current day/hour/min dir
          dateDir
        elsif path == '/favicon.ico'
          [200, {'Content-Type' => 'image/png'}, [SiteIcon]]
        elsif path == '/log'
          log_search                           # search log
        elsif path == '/mail'                  # goto inbox
          [302, {'Location' => '/d?f=msg*'}, []]
        elsif !p.match? /[.:]/                 # no hostname/scheme characters
          timeMeta                             # reference temporally-adjacent nodes
          cacheResponse                        # local node
        else
          if referer = env['HTTP_REFERER']
            referer = referer.R
            env['HTTP_REFERER'] = referer.remoteURL.to_s if referer.host == 'localhost' && referer.path != '/'
          end
          (env[:base] = remoteURL).hostHandler # host handler (rebased on local)
        end
      else
        hostHandler                            # host handler
      end
    end

    def HEAD
      self.GET.yield_self{|s, h, _|
                          [s, h, []]} # status and header
    end

    # headers cleaned/filtered for export
    def headers raw = nil
      raw ||= env || {} # raw headers
      head = {}         # clean headers
      raw.map{|k,v|     # inspect headers
        k = k.to_s
        key = k.downcase.sub(/^http_/,'').split(/[-_]/).map{|t| # strip prefix, tokenize
          if %w{cl dfe dnt id spf utc xsrf}.member? t # acronyms
            t = t.upcase                          # upcase
          else
            t[0] = t[0].upcase                    # capitalize
          end
          t                                       # token
        }.join(k.match?(/(_AP_|PASS_SFP)/i) ? '_' : '-') # join tokens
        head[key] = (v.class == Array && v.size == 1 && v[0] || v) unless %w(base colors connection downloadable feeds fetched graph host images keep-alive links origin-status path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version rack.tempfiles remote-addr repository request-method request-path request-uri resp script-name searchable server-name server-port server-protocol server-software summary sort te transfer-encoding unicorn.socket upgrade upgrade-insecure-requests version via x-forwarded-for).member?(key.downcase)} # external multi-hop headers

      #head['Accept'] = ['text/turtle', head['Accept']].join ',' unless (head['Accept']||'').match?(/text\/turtle/) # accept Turtle

      case host
      when /wsj\.com$/
        head['Referer'] = 'http://drudgereport.com/'
      when /youtube.com$/
        head['Referer'] = 'https://www.youtube.com/'
      end
      head['Referer'] = 'https://' + host + '/' if %w(gif jpeg jpg png svg webp).member? ext.downcase
      head['User-Agent'] = if %w(po.st t.co).member? host # we want shortlink-expansion via HTTP-redirect, not Javascript, so advertise a basic user-agent
                             'curl/7.65.1'
                           else
                             'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.75 Safari/537.36'
                           end
      head
    end

    def hostHandler
      qs = query_values || {}
      cookie = join('/cookie').R
      cookie.writeFile qs['cookie'] if qs.has_key? 'cookie'      # update cookie
      env['HTTP_COOKIE'] = cookie.readFile if cookie.node.exist? # read cookie
      if last = parts[-1]
        if last.match? /^new/
          env[:sort] ||= 'date'
          env[:view] ||= 'table'
        end
      end
      if path == '/favicon.ico' && node.exist?
        fileResponse
      elsif qs['download'] == 'audio'
        storageURI = join(basename + (qs['list'] || qs['v'] || '')+ '.audio').R env
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
      else                       # remote graph-node
        fetch
      end
    end

    def href
      return self if local_node?
      ['http://localhost:8000/', host, path, (query ? ['?', query] : nil), (fragment ? ['#', fragment] : nil) ].join
    end

    def log_search
      env.update({searchable: true, sort: sizeAttr = '#size', view: 'table'})
      results = {}
      if q = (query_values||{})['q']
        `grep -i #{Shellwords.escape 'http.*' + q} ~/web/web.log | tr -s ' ' | cut -d ' ' -f 7 `.each_line{|uri| u = uri.R
          results[uri] ||=  {'uri' => uri,
                             sizeAttr => 0,
                             Title => [[u.host, u.path, (u.query ? ['?', u.query] : nil)].join]}
          results[uri][sizeAttr] += 1}
      end
      [200, {'Content-Type' => 'text/html'}, [(htmlDocument results)]]
    end

    def no_transform?; (query_values||{}).has_key? 'notransform' end

    def notfound; [404, {'Content-Type' => 'text/html'}, [htmlDocument]] end

    def offline?
      ENV.has_key?('OFFLINE') || (query_values||{}).has_key?('offline')
    end

    # Hash -> querystring
    def HTTP.qs h
      return '' if !h || h.empty?
      '?' + h.map{|k,v|
        CGI.escape(k.to_s) + (v ? ('=' + CGI.escape([*v][0].to_s)) : '')
      }.join("&")
    end

    def POST
      require 'httparty'
      if allow_domain?
        head = headers
        body = env['rack.input'].read
        env.delete 'rack.input'
        head.map{|k,v| puts [k,v.to_s].join "\t" }
        puts body
        r = HTTParty.post uri, headers: head, body: body
        head = headers r.headers
        head.map{|k,v| puts [k,v.to_s].join "\t" }
        [r.code, head, [r.body]]
      else
        env[:deny] = true
        [202, {'Access-Control-Allow-Credentials' => 'true',
               'Access-Control-Allow-Origin' => allowed_origin}, []]
      end
    end

    def remoteURL
      ['https:/' , path.sub(/^\/https?:\//,''),
       (query ? ['?', query] : nil),
       (fragment ? ['#', fragment] : nil) ].join.R env
    end

  end
  include HTTP
end
