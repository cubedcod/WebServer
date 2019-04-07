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

    def HTTP.print_body body, mime
      case mime
      when /application\/json/
        puts ::JSON.pretty_generate ::JSON.parse body
      when /application\/x-www-form-urlencoded/
        q = HTTP.parseQs body
        message = q.delete "message"
        puts q
        puts ::JSON.pretty_generate ::JSON.parse message if message
      else
        puts body
      end
    rescue ::JSON::ParserError
      nil
    end

    def HTTP.print_header header; header.map{|k,v|puts [k,v].join "\t"} end

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
        # disallowed name-suffix
        deny
      elsif %w{dash gifv html ico jpg jpg:small jpg:large jpg:thumb jpeg json key ogg m3u8 m4a mp3 mp4 mpd pdf png svg ts vtt webm webp}.member? ext.downcase
        # allowed name-suffix
        remoteNode
      elsif ext == 'gif' && (allowGIF || (%w{i.imgflip.com i.imgur.com s.imgur.com}.member? host))
        # GIF conditionally allowed
        remoteNode
      elsif env['HTTP_REFERER'] && env['HTTP_REFERER'].R.host == 'www.wbur.org'
        # hosts which can import JS from CDN jungle
        remoteNode
      elsif host.match? /(akamai|content|fastly|static)/
        # no suffix-match. fetch and check MIME type of response
        remoteNode.do{|s,h,b|
          if h['Content-Type'] && h['Content-Type'].match?(/^(application.*mpeg|audio|image|video)/)
            [s, h, b]
          else
            deny
          end}
      else
        deny
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
          if cache.noTransform? || UI[@r['SERVER_NAME']]
            cache.localFile # preserve upstream format
          else # transformable
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

    def trackPOST
      env[:deny] = true
      [202,{},[]]
    end

    # ALL_CAPS_CGI format keys to standard HTTP request-header capitalization
    # is there any way to have Rack not do that to the names, or get the original?
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
        # drop rack-internals and Type, our typetag
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

    # Adobe
    '//sp.auth.adobe.com'.R.HTTPthru

    # Amazon
    HostGET['www.amazon.com'] = -> r {
      if %w{gp}.member? r.parts[0]
        r.deny
      else
        r.remoteNode
      end}

    # Anvato
    '//tkx2-prod.anvato.net'.R.HTTPthru
    '//tkx.apis.anvato.net'.R.HTTPthru

    # BizJournal
    HostGET['media.bizj.us'] = -> r {
      if r.path.match? /\*/
        [301, {'Location' => r.path.split(/\*[^.]+\./).join('.')}, []]
      else
        r.remoteNode
      end}

    # BusinessWire
    HostGET['cts.businesswire.com'] = -> r {
      if r.q.has_key? 'url'
        [301, {'Location' => r.q['url']}, []]
      else
        r.remoteNode
      end
    }

    # Brightcove
    '//edge.api.brightcove.com'.R.HTTPthru

    # Broadcastify
    HostPOST['www.broadcastify.com'] = -> r {r.POSTthru}

    # Cloudflare
    HostGET['cdnjs.cloudflare.com'] = HostGET['ajax.googleapis.com'] = -> r {
      if r.path.match? /\/(babel|jquery|react)/
        r.remoteNode
      else
        r.deny
      end}

    # CNN
    HostGET['dynaimage.cdn.cnn.com'] = -> r {[301, {'Location' => 'http' + URI.unescape(r.path.split(/http/)[-1])}, []]}

    # Discourse
    PathGET['/clicks/track'] = -> r {[301,{'Location' => r.q['url']},[]]}

    # Embedly
    HostGET['i.embed.ly'] = -> r {
      if r.path == '/1/display/resize'
        [301, {'Location' => r.q['url']}, []]
      else
        r.deny
      end
    }

    # Facebook
    HostGET['www.facebook.com'] = -> z {
      if %w{ajax api plugins si tr}.member?(z.parts[0]) || z.path.match?(/reaction/) || z.ext == 'php'
        z.deny
      else
        z.remoteNode
      end}

    HostGET['www.instagram.com'] = -> r {
      if false
        r.deny
      else
        r.remoteNode
      end}
    HostGET['instagram.com']   = -> r {[301, {'Location' => "https://www.instagram.com" + r.path},[]]}
    HostGET['l.facebook.com']  = -> r {[301, {'Location' => r.q['u']},  []]}
    HostGET['l.instagram.com'] = -> r {[301, {'Location' => r.q['u']},  []]}
    PathGET['/safe_image.php'] = -> r {[301, {'Location' => r.q['url']},[]]}

    # Forbes
    HostGET['thumbor.forbes.com'] = -> r {
      if r.parts[0] == 'thumbor'
        [301, {'Location' => 'http' + URI.unescape(r.path.split(/http/)[-1])}, []]
      else
        r.remoteNode
      end}

    # Gannett
    #www.gannett-cdn.com

    # Gatehouse
    HostGET['www.patriotledger.com'] = -> r {
      if r.parts[0] == 'storyimage' && r.path.match?(/&/)
        [301, {'Location' => r.path.split('&')[0]},[]]
      else
        r.remoteNode
      end
    }

    # Google
    %w{books drive images maps news}.map{|prod| HostGET[prod + '.google.com'] = -> r {r.remoteNode}}
    HostGET['google.com'] = HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        r.remoteNode
      when /^(aclk|amp|maps|search|webhp)$/
        r.remoteNode
      when 'url'
        [301, {'Location' => ( r.q['url'] || r.q['q'] )}, []]
      else
        r.remoteFiltered
      end}

    HostGET["www.googleadservices.com"] = -> r {
      if r.path == '/pagead/aclk' && r.q.has_key?('adurl')
        [301, {'Location' => r.q['adurl']}, []]
      else
        r.deny
      end
    }

    # Medium
    HostGET['medium.com'] = -> r {
      if %w{_ p}.member? r.parts[0]
        r.deny
      elsif r.path == '/m/global-identity'
        [301, {'Location' => r.q['redirecturl']}, []]
      else
        r.remoteNode
      end}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # QRZ
    HostGET['qrz.com'] = HostGET['forums.qrz.com'] = -> r { r.ext == 'gif' ? r.deny : r.remoteNode }

    # Reddit
    HostGET['i.reddit.com'] = HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[301,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Reuters
    HostGET['s1.reutersmedia.net'] = HostGET['s2.reutersmedia.net'] = HostGET['s3.reutersmedia.net'] = HostGET['s4.reutersmedia.net'] = -> r {
      if r.q.has_key? 'w'
        q = r.q ; q.delete 'w'
        [301, {'Location' => r.path + (HTTP.qs q)}, []]
      else
        r.remoteNode
      end}

    # SoundCloud
    HostGET['exit.sc'] = -> r {[301, {'Location' => r.q['url']},[]]}
    '//api-v2.soundcloud.com'.R.HTTPthru

    # T-Mobile
    HostGET['lookup.t-mobile.com'] = -> re {[200, {'Content-Type' => 'text/html'}, [re.htmlDocument({re.uri => {'dest' => re.q['origurl'].R}})]]}

    # Twitter
    '//api.twitter.com'.R.HTTPthru
    HostGET['mobile.twitter.com'] = HostGET['www.twitter.com'] = -> r {[301, {'Location' =>  "https://twitter.com" + r.path},[]]}
    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter, Link => []}}

        '/twitter'.R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}

        [200, {'Content-Type' => 'text/html'}, [re.htmlDocument(graph)]]
      else
        re.ext == 'js' ? re.deny : re.remoteNode
      end}
    HostGET['t.co'] = -> r {
      if %w{i}.member? r.parts[0]
        r.deny
      else
        r.remoteNode
      end}

    # Univision
    HostOPTIONS['api.vmh.univision.com'] = -> r {r.OPTIONSthru}

    # WaPo
    HostGET['www.washingtonpost.com'] = -> r {
      if r.parts[0] == 'resizer'
        [301, {'Location' =>  'https://' + r.path.split(/\/\d+x\d+\//)[-1]},[]]
      else
        r.remoteNode
      end}
    HostGET['arc-anglerfish-washpost-prod-washpost.s3.amazonaws.com'] = -> r {r.remoteNode}

    # WGBH
    HostGET['wgbh.brightspotcdn.com'] = -> r {
      r.q.has_key?('url') ? [301, {'Location' => r.q['url']}, []] : r.remoteNode
    }

    # YouTube
    HostGET['youtube.com'] = HostGET['m.youtube.com'] = -> r {[301, {'Location' =>  "https://www.youtube.com" + r.path + r.qs},[]]}
    HostGET['youtu.be'] = HostGET['y2u.be'] = -> re {[301,{'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]},[]]}
    HostGET['img.youtube.com'] = -> r {r.remoteFiltered}
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode
        [200, {'Content-Type' => 'text/html'},['<form method="GET" action="/results"><input name="q" autofocus></form>']]
      elsif %w{browse_ajax c channel embed feed get_video_info heartbeat iframe_api live_chat playlist user results signin watch watch_videos yts}.member? mode
        r.remoteNode
      elsif mode == 'redirect'
        [301, {'Location' =>  r.q['q']},[]]
      elsif mode.match? /204$/
        Response_204
      else
        r.deny
      end}
    #'//www.youtube.com'.R.HTTPthru

    # XG
    HostGET['5123.xg4ken.com'] = -> r {r.q.has_key?('url') ? [301, {'Location' => r.q['url']}, []] : r.deny}
  end
end
