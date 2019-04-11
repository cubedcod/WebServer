class WebResource
  module HTTP

    def HTTPthru
      HostGET[host] ||= -> r {r.GETthru}
     HostPOST[host] ||= -> r {r.POSTthru}
  HostOPTIONS[host] ||= -> r {r.OPTIONSthru}
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

    def POSTthru ; verbose = false
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      if verbose
        puts "POST >>> #{url}"
        HTTP.print_header headers
        puts ""
        HTTP.print_body body, @r['CONTENT_TYPE']
      end

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      if verbose
        puts "<<<<<<<<<<<<<<<<<<"
        HTTP.print_header h
        puts ""
        HTTP.print_body b, h['content-type']
        puts ""
      end

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
        end
      else
        remoteNode
      end
    end

    def remoteFiltered allowGIF=false
      if %w{js}.member? ext.downcase
        # drop name-suffix
        deny
      elsif %w{dash html ico jpg jpeg json key ogg m3u8 m4a mp3 mp4 mpd pdf png svg ts vtt webm webp}.member? ext.downcase
        # allow name-suffix
        remoteNode
      elsif ext == 'gif'
        # allow GIF images without query data
        if allowGIF || qs.empty?
          remoteNode
        else
          deny
        end
      else
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
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false # don't follow redirects internally when fetching,
        end # triggers return of redirect metadata for proxy and client book-keeping
      end
      head.delete 'Accept-Encoding'
      head.delete 'Host'
      head.delete 'User-Agent' if host=='t.co' # otherwise redirect only in request-body inside javascript code, not HTTP metadata

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
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
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

    alias_method :GETthru, :remoteNode

    def updateLocation location
      redirectCache.writeFile location
      [302, {'Location' => location}, []]
    end

    UI = {'s.ytimg.com' => true,
      'www.youtube.com' => true}

    # toggle UI provider - local vs origin
    PathGET['/ui/origin'] = -> r {r.q['u'].do{|u| UI[u.R.host] = true; [302, {'Location' => u}, []]} || r.deny }
    PathGET['/ui/local']  = -> r {r.q['u'].do{|u| UI.delete u.R.host;  [302, {'Location' => u}, []]} || r.deny }

    PathGET['/generate_204'] = -> _ {[204, {'Content-Length' => 0}, []]}

    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

  end
end
