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

    def fetch
      head = HTTP.unmangle env # request environment
      response_head = {}      # response environment
      head.delete 'Host'
      head['User-Agent'] = DesktopUA
      head.delete 'User-Agent' if %w{po.st t.co}.member? host

      if @r # redirection
        if relocated?
          location = join(relocation.readFile).R
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false
        end
      end

      # resource pointers
      suffix = ext.empty? && host.match?(/reddit.com$/) && !originUI && '.rss'
      url = 'https://' + host + (path || '') + (suffix || '') + qs
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
              #HTTP.print_header response.meta
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
                cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache' # TODO survey POSIX extended attributes (MIME, source URL) support

                # update index
                updates.concat(case mime
                               when /^(application|text)\/(atom|rss|xml)/
                                 cache.indexFeed
                               when /^text\/html/
                                 # site-specific indexer
                                 IndexHTML[@r ? @r['SERVER_NAME'] : host].do{|indexer| indexer[cache] } || []
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
        begin
          update[url]
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # redirected
          update[url.sub /^https/, 'http']          # HTTPS -> HTTP downgrade retry
        end
      end

      # return value
      if @r # HTTP calling context
        if partialContent
          [206, response_head, [partialContent]]
        elsif cache.exist?
          if cache.noTransform? # immutable-data MIME match
            cache.localFile
          elsif originUI
            cache.localFile     # immutable due to client preference
          else                  # transformable content
            env[:feed] = true if cache.feedMIME?
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script/shell caller
        updates
      end
    rescue OpenURI::HTTPRedirect => re # redirect caller
      updateLocation re.io.meta['location']
    end

    def filter
      if %w{gif js}.member? ext.downcase # filtered suffix
        deny
      else
        fetch.do{|s,h,b|
          if s.to_s.match? /30[1-3]/ # redirected
            [s, h, b]
          else
            if h['Content-Type'] && !h['Content-Type'].match?(/image.(bmp|gif)|script/)
              [s, h, b]
            else # filtered content-type
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
      env['HTTP_USER_AGENT'] == DesktopUA
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
          return fetch if parts.member?('track') && host.match?(/\.(bandcamp|soundcloud)\.com$/)
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
      relocation.writeFile location unless host.match? /(alibaba|google|soundcloud|twitter|youtube)\.com$/
      [302, {'Location' => location}, []]
    end

  end
end
