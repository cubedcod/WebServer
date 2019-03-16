class WebResource
  module HTTP
    def amp
      [301, {'Location' => 'https://' + (host.split('.') - %w{amp}).join('.') + (path.split('/') - %w{amp amphtml}).join('/')}, []]
    end

    def cdn
      if %w{css html jpg jpg:large jpeg ogg m3u8 m4a mp3 mp4 pdf png svg ts webm webp}.member? ext.downcase
        remoteNode
      else
        deny
      end
    end

    def GETthru
      head = HTTP.unmangle env
      head.delete 'Host'
      formatSuffix = (host.match?(/reddit.com$/) && !parts.member?('w')) ? '.rss' : ''
      portNum = port && !([80,443,8000].member? port) && ":#{port}" || ''
      queryHash = q
      queryHash.delete 'host'
      queryString = queryHash.empty? ? '' : (HTTP.qs queryHash)
      urlHTTPS = scheme && scheme=='https' && uri || ('https://' + host + portNum + path + formatSuffix + queryString)
      urlHTTP  = 'http://'  + host + portNum + (path||'/') + formatSuffix + queryString
      cache = cacheFile
      cacheMeta = cache.metafile

      # lazy updater, called by need
      updates = []
      update = -> url {
        begin # block to catch 304-response "error"
          open(url, head) do |response| # response

            if @r # HTTP-request calling context - preserve origin bits
              @r[:Response]['Access-Control-Allow-Origin'] ||= '*'
              response.meta['set-cookie'].do{|cookie| @r[:Response]['Set-Cookie'] = cookie}
            end

             # index updates
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # cache body
              mime = response.meta['content-type'].do{|type| type.split(';')[0] } || ''
              cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache' # file metadata (TODO POSIX-eattrs for MIME)
              # index content
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
        rescue OpenURI::HTTPError => e
          raise unless e.message.match? /304/
        end}

      # conditional update
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
        begin # prefer HTTPS w/ fallback HTTP attempt
          update[urlHTTPS]
        rescue
          update[urlHTTP]
        end
        cacheMeta.touch if cacheMeta.e # bump timestamp
      end

      # response
      if @r # HTTP calling context
        if cache.exist?
          # preserve upstream format?
          if cache.noTransform?
            cache.fileResponse
          else # transformable
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script/shell caller
        updates.empty? ? self : updates
      end

    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts msg, trace
      @r ? [500, {'Content-Type' => 'text/html'},
            [htmlDocument({uri => {Content => [{_: :style, c: "body {background-color: red !important}"},
                                               {_: :h3, c: msg.hrefs}, {_: :pre, c: trace.hrefs},
                                               {_: :h4, c: 'request'},
                                               (HTML.kv (HTML.urifyHash head), @r), # request header
                                               ([{_: :h4, c: "response #{e.io.status[0]}"},
                                                (HTML.kv (HTML.urifyHash e.io.meta), @r), # response header
                                                (CGI.escapeHTML e.io.read.to_utf8)] if e.respond_to? :io) # response body
                                              ]}})]] : self
    end
    alias_method :remoteNode, :GETthru

    def HTTPthru
      HostGET[host] = -> r {r.GETthru}
     HostPOST[host] = -> r {r.POSTthru}
  HostOPTIONS[host] = -> r {r.OPTIONSthru}
    end

    def OPTIONSthru
      verbose = false

      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      HTTP.print_header headers if verbose
      HTTP.print_body body, headers['Content-Type'] if verbose

      # response
      r = HTTParty.options url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      HTTP.print_header h if verbose
      HTTP.print_body b, h['Content-Type'] if verbose
      [s, h, [b]]
    end

    def POSTthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      #HTTP.print_header headers
      #HTTP.print_body body, headers['Content-Type']

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      #HTTP.print_header h
      #HTTP.print_body b, h['Content-Type']
      [s, h, [b]]
    end

    def trackPOST
      env[:deny] = true
      [202,{},[]]
    end

    PathGET['/cache'] = -> cache {
      cache.q['url'].do{|url|
        r = url.R cache.env
        if r.host == 'bit.ly'
          r.cachedRedirect
        elsif %w{png jpg webp}.member? r.ext
          ('//' + r.host + r.path).R(cache.env).remoteNode
        else
          r.remoteNode
        end
      } || [200, {'Content-Type' => 'text/html'}, ['<form method="GET"><input name="url" autofocus></form>']]}

    PathGET['/generate_204'] = -> _ {Response_204}

    PathGET['/music'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

    # Discourse
    PathGET['/clicks/track'] = -> r {[301,{'Location' => r.q['url']},[]]}

    # DuckDuckGo
    ['',0,1,2,3,4].map{|n|
      HostGET['proxy'+n.to_s+'.duckduckgo.com'] = -> re {
        case re.parts[0]
        when 'iu'
          [301,{'Location' => re.q['u'],
                'Access-Control-Allow-Origin' => '*'
               },[]]
        when 'iur'
          [301,{'Location' => re.q['image_host']},[]]
        when 'ip3'
          re.ext == 'ico' ? re.favicon : re.notfound
        when 'mapboxapi'
          re.remoteNode
        when 'mapkit'
          original = re.env['QUERY_STRING'].R re.env
          original.env['QUERY_STRING'] = original.query
          original.remoteNode
        else
          re.notfound
        end}}

    # eBay
    HostGET['rover.ebay.com'] = -> r {
      if r.parts[0] == 'rover'
        [301, {'Location' => r.q['mpre']}, []]
      else
        r.deny
      end
    }

    # Embedly
    HostGET['i.embed.ly'] = -> r {
      if r.path == '/1/display/resize'
        [301, {'Location' => r.q['url']}, []]
      else
        r.deny
      end
    }

    # Facebook
    HostGET['www.facebook.com'] = -> zuck {
      if zuck.ext == 'php'
        zuck.deny
      else
        zuck.remoteNode
      end}
    PathGET['/safe_image.php'] = -> r {[301,{'Location' => r.q['url']},[]]}

    # Gatehouse
    HostGET['www.patriotledger.com'] = -> r {
      if r.parts[0] == 'storyimage' && r.path.match?(/&/)
        [301, {'Location' => r.path.split('&')[0]},[]]
      else
        r.remoteNode
      end
    }

    # Google
    %w{mail news}.map{|_|
      "//#{_}.google.com".R.HTTPthru}

    %w{feedproxy.google.com gmail.com google.com}.map{|h|
      HostGET[h] = -> r {r.cachedRedirect}}

    HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when /^(amp|gmail)$/
        r.cachedRedirect
      when /^(maps|search)$/
        r.remoteNode
      when 'url'
        [301, {'Location' => ( r.q['q'] || r.q['url'] )}, []]
      else
        r.cdn
      end}

    # IG
    HostGET['instagram.com'] = -> r {[301, {'Location' =>  "https://www.instagram.com" + r.path},[]]}
    HostGET['l.instagram.com'] = -> r {[301,{'Location' => r.q['u']},[]]}

    # Imgur
    HostGET['imgur.com'] = HostGET['i.imgur.com'] = -> re {
      if !re.ext.empty? # file extension
        if 'i.imgur.com' == re.host # image host
          re.remoteNode # cached image
        else # redirect to image host
          [301,{'Location' => 'https://i.imgur.com' + re.path},[]]
        end
      else # redirect to image file
        UnwrapImage[re]
      end}

    # Medium
    HostGET['medium.com'] = -> r {
      if %w{_ p}.member? r.parts[0]
        r.deny
      elsif r.path == '/m/global-identity'
        [301, {'Location' => r.q['redirecturl']}, []]
      else
        r.remoteNode
      end}

    # Mixcloud
    HostPOST['www.mixcloud.com'] = -> r {r.path == '/graphql' ? r.POSTthru : r.trackPOST}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Reddit
    HostGET['i.reddit.com'] = HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[301,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Soundcloud
    HostGET['exit.sc'] = -> r {[301, {'Location' => r.q['url']},[]]}

    # YouTube
    '//accounts.youtube.com'.R.HTTPthru
    HostGET['youtube.com'] = HostGET['m.youtube.com'] = -> r {[301, {'Location' =>  "https://www.youtube.com" + r.path + r.qs},[]]}
    HostGET['youtu.be'] = HostGET['y2u.be'] = -> re {[301,{'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]},[]]}
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

    # T-Mobile
    HostGET['lookup.t-mobile.com'] = -> re {[200, {'Content-Type' => 'text/html'}, [re.htmlDocument({re.uri => {'dest' => re.q['origurl'].R}})]]}

    # Twitter
    HostGET['mobile.twitter.com'] = HostGET['www.twitter.com'] = -> r {[301, {'Location' =>  "https://twitter.com" + r.path},[]]}
    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter, Link => []}}

        '/twitter'.R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}

        [200, {'Content-Type' => 'text/html'}, [re.htmlDocument(graph)]]
      else
        re.remoteNode
      end}

  end
end
