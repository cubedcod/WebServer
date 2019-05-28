# coding: utf-8
class WebResource
  module HTTP

    def cacheFile
      pathname = path || ''
      pathname = pathname[-1] == '/' ? pathname[0..-2] : pathname # strip trailing slash
      keep_ext = %w{aac atom css html jpeg jpg js m3u8 map mp3 mp4 ogg opus pdf png rdf svg ttf ttl vtt webm webp woff woff2}.member?(ext.downcase) && !host&.match?(/openload|\.wiki/)
      ((host ? ('/' + host) : '') + (if qs && !qs.empty? # hashed query
                                     [pathname, qs.sha2, keep_ext ? ext : 'cache'].join '.'
                                    else
                                      keep_ext ? pathname : (pathname + '.cache')
                                     end)).R env
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

    def fetch
      # environment
      head = HTTP.unmangle env
      head.delete 'Host'
      head['User-Agent'] = DesktopUA
      head.delete 'User-Agent' if %w{po.st t.co}.member? host

      # relocation handling
      if @r
        if relocated?
          location = join(relocation.readFile).R
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false
        end
      end

      # resource pointers and metadata
      suffix = ext.empty? && host.match?(/reddit.com$/) && !originUI && '.rss'
      url = 'https://' + host + (path || '') + (suffix || '') + qs
      cache = cacheFile
      partial_response = nil
      cacheMeta = cache.metafile
      head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
      response_meta = {}
      updates = []

      # fetcher lambda
      fetchURL = -> url {
        print '🌍🌎🌏'[rand 3], ' '#, url, ' '
        begin
          open(url, head) do |response| # request
            if response.status.to_s.match?(/206/) # partial response
              response_meta = response.meta
              partial_response = response.read
            else # response
              %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k| @r[:Response][k] ||= response.meta[k.downcase] } if @r
              body = decompress response.meta, response.read
              unless cache.e && cache.readFile == body # unchanged
                # update cache
                cache.writeFile body
                mime = if response.meta['content-type'] # explicit MIME
                         response.meta['content-type'].split(';')[0]
                       elsif MIMEsuffix[cache.ext]      # file extension
                         MIMEsuffix[cache.ext]
                       else                             # sniff
                         cache.mimeSniff
                       end
                # updata metadata on cache file  TODO survey POSIX eattr support
                cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache'
                # index updates
                updates.concat(case mime
                               when /^(application|text)\/(atom|rss|xml)/
                                 cache.indexFeed
                               when /^text\/html/
                                 IndexHTML[@r ? @r['SERVER_NAME'] : host].do{|indexer| indexer[cache] } || []
                               else
                                 []
                               end || [])
              end
            end
          end
        rescue Exception => e
          raise unless e.message.match? /[34]04/ # 304/404 handled in normal control-flow
        end}

      # update cache
      unless cache.noTransform? || OFFLINE
        begin
          fetchURL[url]                             # HTTPS
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # redirected
          fetchURL[url.sub /^https/, 'http']        # HTTP downgrade
        end
      end

      # response
      if @r # HTTP caller
        if partial_response
          [206, response_meta, [partial_response]]
        elsif cache.exist?
          if cache.noTransform?
            cache.localFile # immutable format
          elsif originUI
            cache.localFile # upstream format
          else              # output transform
            env[:feed] = true if cache.feedMIME?
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script caller
        updates
      end
    rescue OpenURI::HTTPRedirect => re # redirected
      updateLocation re.io.meta['location']
    end

    def filter
      if %w{gif js}.member? ext.downcase # filtered name-suffix
        if ext=='gif' && qs.empty?
          fetch
        else
          deny
        end
      else
        fetch.do{|s,h,b|
          if s.to_s.match? /30[1-3]/ # redirected
            [s, h, b]
          else
            if h['Content-Type'] && !h['Content-Type'].match?(/image.(bmp|gif)|script/)
              [s, h, b]
            else # filtered MIME
              deny
            end
          end}
      end
    end

    def GETthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      # response
      r = HTTParty.get url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      [s, h, [b]]
    end

    def metafile type = 'meta'
      dir + (dirname[-1] == '/' ? '' : '/') + '.' + basename + '.' + type
    end

    OFFLINE = ENV.has_key? 'OFFLINE'

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

    def originUI
      if %w{duckduckgo.com soundcloud.com}.member? host
        true
      elsif env['HTTP_USER_AGENT'] == DesktopUA
        true
      else
        false
      end
    end

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

    def remote
      if env.has_key? 'HTTP_TYPE'
        case env['HTTP_TYPE']
        when /drop/
          if ((host.match? /track/) || (env['REQUEST_URI'].match? /track/)) && (host.match? TrackHost)
            fetch
          elsif qs == '?allow'
            puts "ALLOW #{uri}"
            env.delete 'QUERY_STRING'
            fetch
          else
            drop
          end
        when /filter/
          filter
        when /thru/
          self.GETthru
        end
      else
        fetch
      end
    end

    def updateLocation location
      # TODO declare non-301/permcache somewhere better than here
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|twitter|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

  end
end
