class WebResource
  module HTTP

    def cache?; !(pragma && pragma == 'no-cache') end

    def localNode?
      %w{l [::1] 127.0.0.1 localhost}.member? @r['SERVER_NAME']
    end

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

    def pragma; env['HTTP_PRAGMA'] end

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

    def remoteFiltered allowGIF=false
      if %w{js}.member? ext.downcase
        # disallowed name-suffixes
        deny
      elsif %w{dash gifv html ico jpg jpg:small jpg:large jpg:thumb jpeg json key ogg m3u8 m4a mp3 mp4 mpd pdf png svg ts vtt webm webp}.member? ext.downcase
        # allowed name-suffixes
        remoteNode
      elsif ext == 'gif'
        # conditionally allow GIF images
        if allowGIF || %w{i.imgflip.com i.imgur.com s.imgur.com}.member?(host) #|| qs.empty?
          remoteNode
        else
          deny
        end
      else
        # fetch and validate MIME type of response
        remoteNode.do{|s,h,b|
          if h['Content-Type'] && h['Content-Type'].match?(/application\/.*mpeg|audio\/|image\/|video\/|octet-stream/) && !h['Content-Type'].match?(/^image\/gif/)
            [s, h, b]
          else
            deny
          end}
      end
    end

    def remoteNode
      head = HTTP.unmangle env # HTTP header
      if @r # HTTP calling
        if redirection
          location = join(redirectCache.readFile).R
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false # don't follow redirects internally when fetching
        end
      end
      head.delete 'Accept-Encoding'
      head.delete 'Host'
      head.delete 'User-Agent' if host=='t.co' # prefer location in HTTP header, not javascript code

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
              # update index
              updates.concat(case mime
                             when /^(application|text)\/(atom|rss|xml)/
                               cache.indexFeed
                             when /^text\/html/
                               cache.indexHTML host
                             else
                               []
                             end || [])
            end
          end
        rescue Exception => e
          raise unless e.message.match? /[34]04/ # notModified and notFound in normal control-flow
        end}

      # conditional updater
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        begin
          update[url] # try HTTPS
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # exit with redirection
          update[url.sub /^https/, 'http'] # fetch HTTP
        end
        cacheMeta.touch if cacheMeta.e # mark update-time
      end

      # return value
      if @r # HTTP calling-context
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
      else # REPL/script/shell calling-context
        updates.empty? ? cache : updates
      end

    rescue OpenURI::HTTPRedirect => re
      updateLocation re.io.meta['location']
    end

    alias_method :GETthru, :remoteNode

    def trackPOST; verbose = true
      env[:deny] = true
      if verbose
        puts "POST >>> #{url}"
        HTTP.print_header headers
        puts ""
        HTTP.print_body body, @r['CONTENT_TYPE']
      end
      [202,{},[]]
    end

    # CAPS_CGI format keys to standard HTTP request-header capitalization
    # is there any way to have Rack not do that to the names?
    def self.unmangle env
      head = {}
      env.map{|k,v|
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split('_').map{|k| # chop prefix and tokenize
          if %w{cl id spf utc xsrf}.member? k # acronyms to capitalize
            k = k.upcase
          else
            k[0] = k[0].upcase # word
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored
        # drop internal-use headers
        head[key] = v.to_s unless %w{links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}
      head
    end

    def updateLocation location
      redirectCache.writeFile location
      [302, {'Location' => location}, []]
    end

    UI = {'s.ytimg.com' => true,
      'www.youtube.com' => true}

    # toggle UI provider - local vs origin
    PathGET['/ui/origin'] = -> r {r.q['u'].do{|u| UI[u.R.host] = true; [302, {'Location' => u}, []]} || r.deny }
    PathGET['/ui/local']  = -> r {r.q['u'].do{|u| UI.delete u.R.host;  [302, {'Location' => u}, []]} || r.deny }

    PathGET['/generate_204'] = -> _ {Response_204}

    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

  end
end
