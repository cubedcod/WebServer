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

    def metafile type = 'meta'
      dir + (dirname[-1] == '/' ? '' : '/') + '.' + basename + '.' + type
    end

    def fetch
      head = HTTP.unmangle env # request environment
      response_head = {}      # response environment
      head.delete 'Host'
      head.delete 'User-Agent' if %w{po.st t.co}.member? host

      if @r # redirector
        if relocated?
          location = join(relocation.readFile).R
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false
        end
      end

      # storage pointer
      cache = cacheFile
      cacheMeta = cache.metafile
      head["If-Modified-Since"] = cache.mtime.httpdate if cache.e

      # updater
      partialContent = nil
      updates = []
      update = -> url {
        print '🌎🌏🌍'[rand 3], ' '
        begin
          open(url, head) do |response| # request
            if response.status.to_s.match?(/206/) # partial response
              response_head = response.meta
              partialContent = response.read
            else # response
              %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k| @r[:Response][k] ||= response.meta[k.downcase] } if @r
              body = response.read

              # decompress
              case response.meta['content-encoding'].to_s
              when /^br(otli)?$/
                body = Brotli.inflate body
              when /gzip/
                body = (Zlib::GzipReader.new StringIO.new body).read
              when /flate|zip/
                body = Zlib::Inflate.inflate body
              end

              # update cache
              unless cache.e && cache.readFile == body
                cache.writeFile body
                mime = if response.meta['content-type'] # explicit MIME
                         response.meta['content-type'].split(';')[0]
                       elsif MIMEsuffix[cache.ext]      # file extension
                         MIMEsuffix[cache.ext]
                       else                             # sniff
                         cache.mimeSniff
                       end
                # cache metadata TODO survey POSIX extended attributes support
                cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache'

                # index updates
                updates.concat(case mime
                               when /^(application|text)\/(atom|rss|xml)/
                                 cache.storeFeed
                               when /^text\/html/
                                 # site-specific indexer
                                 IndexHTML[@r['SERVER_NAME']].do{|indexer| indexer[cache] } || []
                               else
                                 []
                               end || [])
              end
            end
          end
        rescue Exception => e
          if e.message.match? /[34]04/
            # resource unchanged or missing
          else
            raise # miscellaneous errors
          end
        end}

      # refresh cache
      immutable = cache? && cache.e && cache.noTransform?
      unless immutable || OFFLINE
        # resource location
        suffix = ext.empty? && host.match?(/reddit.com$/) && !UI[@r['SERVER_NAME']] && '.rss'
        url = 'https://' + host + (path||'') + (suffix||'') + qs 
        begin
          update[url]
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # follow redirection
          update[url.sub /^https/, 'http']          # HTTPS -> HTTP downgrade and retry
        end
      end

      # return value
      if @r # HTTP
        if partialContent
          [206, response_head, [partialContent]]
        elsif cache.exist?
          if cache.noTransform? # immutable format
            cache.localFile
          elsif UI[@r['SERVER_NAME']] # upstream controls format
            cache.localFile
          else # transform to negotiated format
            env[:feed] = true if cache.feedMIME?
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/shell
        updates.empty? ? cache : updates
      end
    rescue OpenURI::HTTPRedirect => re # redirect caller
      updateLocation re.io.meta['location']
    end

    def filter
      if %w{gif js}.member? ext.downcase # blocked suffixes
        deny
      else
        fetch.do{|s,h,b|
          if s.to_s.match? /30[1-3]/ # redirection
            [s, h, b]
          else
            if h['Content-Type'] && !h['Content-Type'].match?(/image.(bmp|gif)|script/)
              [s, h, b]
            else
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

    def POSTthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      headers.delete 'Accept-Encoding'
      body = env['rack.input'].read

      puts "->"
      HTTP.print_header headers
      HTTP.print_body body, headers['Content-Type']

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      body = if h['content-encoding'].to_s.match?(/zip/)
               Zlib::Inflate.inflate(b) rescue ''
             else
               b
             end

      puts "<-"
      HTTP.print_header h
      HTTP.print_body body, h['content-type']

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
          drop
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
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

  end
end
