class WebResource
  module HTTP
    OFFLINE = ENV.has_key? 'OFFLINE'

    def cacheFile
      p = path || ''
      keep_ext = %w{aac atom css html jpeg jpg js m3u8 map mp3 mp4 ogg opus pdf png rdf svg ttf ttl vtt webm webp woff woff2}.member?(ext.downcase) && !host&.match?(/openload|\.wiki/)
      ((host ? ('/' + host) : '') + (if host&.match?(/google|static|\.redd/) || (qs && !qs.empty?) # mint path
                     hash = (p + qs).sha2                              # hash upstream path
                     type = keep_ext ? ext : 'cache'                   # append format-suffix
                     '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # distribute to balanced bins
                    else                                               # preserve upstream path
                      name = p[-1] == '/' ? p[0..-2] : p               # strip trailing-slash
                      name + (keep_ext ? '' : '.cache')                # append format-suffix
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
      headers.delete 'Accept-Encoding'
      body = env['rack.input'].read
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
      HTTP.print_header h
      HTTP.print_body body, h['content-type']
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
      if parts[-1].to_s.match? /^g.*204$/
        [204, {'Content-Length' => 0}, []]
      elsif env.has_key? 'HTTP_TYPE'
        case env['HTTP_TYPE']
        when /drop/
          if path.match?('/track') && host.match?(/(bandcamp|soundcloud).com$/)
            remoteNode
          else
            deny
          end
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
      # filter on URI
      if %w{bin js pb}.member? ext.downcase
        if cacheFile.exist?
          cacheFile.localFile
        else
          deny
        end
      elsif %w{css dash html ico jpg jpeg json key ogg m3u8 m4a mp3 mp4 mpd pdf png svg ts vtt webm webp}.member? ext.downcase # allow name-suffix
        remoteNode
      elsif ext == 'gif'
        if allowGIF || qs.empty?
          remoteNode
        else
          deny
        end
      else # fetch and inspect
        remoteNode.do{|s,h,b|
          if s.to_s.match? /30[1-3]/ # redirected
            [s, h, b]
          else
            if h['Content-Type']
              (h['Content-Type'].match? /image.(bmp|gif)|script/) ? deny : [s, h, b]
            else
              deny
            end
          end}
      end
    end

    def remoteNode
      head = HTTP.unmangle env # request header
      responseHead = {}       # response header
      if @r # HTTP context
        if redirection
          location = join(redirectCache.readFile).R
          # redirect caller
          return redirect unless location.host == host && (location.path || '/') == path
        else
          head[:redirect] = false
        end
      end
      head.delete 'Accept-Encoding'
      head.delete 'Host'
      head['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3773.0 Safari/537.36'
      head['Referer'] = 'http://drudgereport.com/' if host.match? /www.(wsj).com$/ # thanks, Matt
      head.delete 'User-Agent' if %w{t.co}.member? host # don't advertise JS-capability or HTTP header data goes missing
      suffix = ext.empty? && host.match?(/reddit.com$/) && !parts.member?('wiki') && !UI[@r['SERVER_NAME']] && '.rss' # format suffix
      url = if @r && !suffix && !(path||'').match?(/[\[\]]/) # preserve locator
              "https://#{host}#{@r['REQUEST_URI']}"
            else # construct locator
              'https://' + host + (path||'').gsub('[','%5B').gsub(']','%5D') + (suffix||'') + qs
            end
      cache = cacheFile # storage pointer
      head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
      cacheMeta = cache.metafile # storage metadata
      part = nil
      updates = []
      update = -> url { # updater lambda
#        puts "GET " + url
        begin
          open(url, head) do |response|
            if response.status.to_s.match?(/206/) # partial response
              responseHead = response.meta
              part = response.read
            else # index and store full response
              %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k| @r[:Response][k] ||= response.meta[k.downcase] } if @r # origin-metadata to caller
              body = response.read
              unless cache.e && cache.readFile == body
                cache.writeFile body # update cache
                mime = if response.meta['content-type'] # explicit MIME
                         response.meta['content-type'].split(';')[0]
                       elsif MIMEsuffix[cache.ext]      # file extension
                         MIMEsuffix[cache.ext]
                       else                             # sniff
                         cache.mimeSniff
                       end
                cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache' # write metadata
                updates.concat(case mime                                              # update index
                               when /^(application|text)\/(atom|rss|xml)/
                                 cache.storeFeed
                               when /^text\/html/
                                 cache.storeHTML
                               else
                                 []
                               end || [])
              end
            end
          end
        rescue Exception => e
          if e.message.match? /[34]04/
            # not-modified/found handled in normal control-flow
          elsif e.message.match? /503/
            puts e.io
            return [503,{'Content-Type' => 'text/html'}, [503]]
          else
            raise # miscellaneous errors
          end
        end}
      # update
      immutable = cache? && cache.e && cache.noTransform?
      unless immutable || OFFLINE
        begin
          update[url] # HTTPS
        rescue Exception => e
          raise if e.class == OpenURI::HTTPRedirect # redirect
          update[url.sub /^https/, 'http'] # HTTPS failed, try HTTP
        end
      end
      # return updates to caller
      if @r # HTTP calling context
        if part
          [206, responseHead, [part]]
        elsif cache.exist?
          if cache.noTransform?
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
    rescue OpenURI::HTTPRedirect => re # return redirect-exception as HTTP response
      updateLocation re.io.meta['location']
    end

    def updateLocation location
      redirectCache.writeFile location
      [302, {'Location' => location}, []]
    end

    UI = {'s.ytimg.com' => true}

    # toggle UI provider - local vs origin
    PathGET['/ui/origin'] = -> r {r.q['u'].do{|u| UI[u.R.host] = true; [302, {'Location' => u}, []]} || r.deny }
    PathGET['/ui/local']  = -> r {r.q['u'].do{|u| UI.delete u.R.host;  [302, {'Location' => u}, []]} || r.deny }

    PathGET['/url'] = -> r { [301, {'Location' => (r.q['url']||r.q['q'])}, []]}
    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

  end
end
