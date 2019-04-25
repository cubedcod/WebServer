class WebResource
  module HTTP
    OFFLINE = ENV.has_key? 'OFFLINE'

    def cacheFile
      p = path || ''
      keep_ext = %w{aac atom css html jpeg jpg js m3u8 map mp3 mp4 ogg opus pdf png rdf svg ttf ttl vtt webm webp woff woff2}.member?(ext.downcase) && !host&.match?(/\.wiki/)
      ((host ? ('/' + host) : '') + (if host&.match?(/google|static|\.redd/) || (qs && !qs.empty?) # mint path
                     hash = (p + qs).sha2                              # hash upstream path
                     type = keep_ext ? ext : 'cache'               # append format-suffix
                     '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # distribute to balanced bins
                    else                                    # upstream path
                      name = p[-1] == '/' ? p[0..-2] : p    # strip trailing-slash
                      name + (keep_ext ? '' : '.cache') # append format-suffix
                     end)).R env
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
      body = env['rack.input'].read

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body

      [s, h, [b]]
    end

    def redirectCache
      hash = (host + (path || '') + qs).sha2
      ('/cache/location/' + hash[0..2] + '/' + hash[3..-1] + '.u').R
    end

    def redirect
      [302, {'Location' => redirectCache.readFile}, []]
    end

    def redirection
      redirectCache.exist?
    end

    def remote
      if env.has_key? 'HTTP_TYPE'
        case env['HTTP_TYPE']
        when /drop/
          deny
        when /filter/
          remoteFiltered
        when /thru/
          self.GETthru
        end
      else
        remoteNode
      end
    end

    def remoteFiltered allowGIF=false
      # filter URIs
      if %w{bin js pb}.member? ext.downcase # drop name-suffix
        if cacheFile.exist?
          puts "#{uri} cache exists, delivering"
          cacheFile.localFile
        else
          deny
        end
      elsif %w{css dash html ico jpg jpeg json key ogg m3u8 m4a mp3 mp4 mpd pdf png svg ts vtt webm webp}.member? ext.downcase # allow name-suffix
        remoteNode
      elsif ext == 'gif'
#        if allowGIF || qs.empty?
#          remoteNode
#        else # strip GIF images with query data
          deny
#        end
      else # filter MIME types
        remoteNode.do{|s,h,b|
          if h['Content-Type'] && h['Content-Type'].match?(/application\/.*mpeg|audio\/|image\/|text\/html|video\/|octet-stream/) && !h['Content-Type'].match?(/^image\/gif/)
            # allow MIME type
            [s, h, b]
          else
            # drop MIME type
            deny
          end}
      end
    end

    def remoteNode
      head = HTTP.unmangle env # HTTP header
      if @r # HTTP context
        if redirection
          location = join(redirectCache.readFile).R
          # direct caller to updated location
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false # don't follow redirects internally
        end
      end
      head.delete 'Accept-Encoding'
      head.delete 'Host'
      head['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3773.0 Safari/537.36'
      head.delete 'User-Agent' if %w{t.co}.member? host # don't advertise JS capability

      # explicit-format suffix
      suffix = ext.empty? && host.match?(/reddit.com$/) && !parts.member?('wiki') && !UI[@r['SERVER_NAME']] && '.rss'

      url = if @r && !suffix && !(path||'').match?(/[\[\]]/) # preserve URI
              "https://#{host}#{@r['REQUEST_URI']}"
            else # construct locator
              'https://' + host + (path||'').gsub('[','%5B').gsub(']','%5D') + (suffix||'') + qs
            end
      cache = cacheFile # cache-storage pointer
      head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
      cacheMeta = cache.metafile # cache metadata
      updates = []

      update = -> url { # lazy lambda
        begin
          open(url, head) do |response| # response
            # origin-metadata for caller
            %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k|
              @r[:Response][k] ||= response.meta[k.downcase]} if @r
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # write cache
              mime = if response.meta['content-type'] # explicit MIME from upstream
                       response.meta['content-type'].split(';')[0]
                     elsif MIMEsuffix[cache.ext]      # file extension
                       MIMEsuffix[cache.ext]
                     else                             # sniff
                       cache.mimeSniff
                     end
              cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache' # write metadata
              # call indexer
              updates.concat(case mime
                             when /^(application|text)\/(atom|rss|xml)/
                               cache.indexFeed
                             when /^text\/html/
                               cache.indexHTML
                             else
                               []
                             end || [])
            end
          end
        rescue Exception => e
          raise unless e.message.match? /[34]04/ # notModified and notFound in normal control-flow
        end}

      # update
      immutable = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless immutable || OFFLINE || throttled
        begin
          update[url] # try HTTPS
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # redirected, go book-keep
          update[url.sub /^https/, 'http'] # HTTPS failed, try HTTP
        end
        cacheMeta.touch if cacheMeta.e # update timestamp
      end

      # return value
      if @r # HTTP caller
        if cache.exist?
          if cache.noTransform? # upstream formats
            cache.localFile
          elsif UI[@r['SERVER_NAME']]
            cache.localFile
          else # transformable data
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/shell caller
        updates.empty? ? cache : updates
      end

    rescue OpenURI::HTTPRedirect => re
      updateLocation re.io.meta['location']
    end

    def updateLocation location
      redirectCache.writeFile location
      [302, {'Location' => location}, []]
    end

    UI = {
      'duckduckgo.com' => true,
      's.ytimg.com' => true,
      'www.youtube.com' => true,
    }

    # toggle UI provider - local vs origin
    PathGET['/ui/origin'] = -> r {r.q['u'].do{|u| UI[u.R.host] = true; [302, {'Location' => u}, []]} || r.deny }
    PathGET['/ui/local']  = -> r {r.q['u'].do{|u| UI.delete u.R.host;  [302, {'Location' => u}, []]} || r.deny }

    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

  end
end
