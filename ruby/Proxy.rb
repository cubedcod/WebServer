class WebResource
  module HTTP

    def amp
      [301, {'Location' => 'https://' + (host.split('.') - %w{amp}).join('.') + (path.split('/') - %w{amp amphtml}).join('/')}, []]
    end

    def cache?; !(pragma && pragma == 'no-cache') end

    def localResource?
      %w{l [::1] 127.0.0.1 localhost}.member? @r['SERVER_NAME']
    end

    def HTTPthru
      HostGET[host] = -> r {r.GETthru}
     HostPOST[host] = -> r {r.POSTthru}
  HostOPTIONS[host] = -> r {r.OPTIONSthru}
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
      #puts s,b; print_header
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

    def print_body
      @r['rack.input'].do{|i|
        HTTP.print_body i.read, @r['CONTENT_TYPE'] }
    end

    def HTTP.print_header header
      header.map{|k,v|
        puts [k,v].join "\t"}
    end

    def print_header
      HTTP.print_header env
    end

    def remoteFile allowGIF=false
      if %w{html jpg jpg:small jpg:large jpg:thumb jpeg ogg m3u8 m4a mp3 mp4 pdf png svg ts vtt webm webp}.member? ext.downcase
        remoteNode
      elsif allowGIF && ext == 'gif'
        remoteNode
      else
        deny
      end
    end

    def remoteNode
      head = HTTP.unmangle env # unCGIify header key-names
      suffix = host.match?(/reddit.com$/) && !parts.member?('wiki') && '.rss' # format suffix
      url = if @r && !suffix # unmodified URI from environment
              "https://#{host}#{@r['REQUEST_URI']}"
            else
              'https://' + host + (path||'') + (suffix||'') + qs
            end
      cache = cacheFile
      cacheMeta = cache.metafile
      updates = []

      # lazy updater
      update = -> url {
        begin # block to catch 304-status "error"
          open(url, head) do |response| # response
            # origin-metadata for caller
            %w{Access-Control-Allow-Origin Access-Control-Allow-Credentials Set-Cookie}.map{|k|
              @r[:Response][k] ||= response.meta[k.downcase]} if @r
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # update cache
              mime = response.meta['content-type'].do{|type| type.split(';')[0] } || ''
              cacheMeta.writeFile [mime, url, ''].join "\n" if cache.ext == 'cache' # cache-file metadata (TODO POSIX-eattrs for MIME)
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
        rescue OpenURI::HTTPError => e
          raise unless e.message.match? /304/
        end}

      # conditional update
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
        begin # prefer HTTPS
          update[url]
        rescue
          update[url.sub /^https/, 'http']
        end
        cacheMeta.touch if cacheMeta.e # bump timestamp
      end

      # response
      if @r # HTTP calling context
        if cache.exist?
          # preserve upstream format?
          if cache.noTransform? || UI[@r['SERVER_NAME']]
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
    alias_method :GETthru, :remoteNode

    def trackPOST
      env[:deny] = true
      [202,{},[]]
    end

    UI = {'www.youtube.com' => true,
          's.ytimg.com' => true,
          'sdr.hu' => true,
          'e.infogram.com' => true,
          'cpt-static.gannettdigital.com' => true}

    # toggle UI provider - local vs origin
    PathGET['/ui/origin'] = -> r {r.q['u'].do{|u| UI[u.R.host] = true; [302, {'Location' => u}, []]} || r.deny }
    PathGET['/ui/local']  = -> r {r.q['u'].do{|u| UI.delete u.R.host;  [302, {'Location' => u}, []]} || r.deny }

=begin
    # explicit cache-request for URL
    PathGET['/cache'] = -> cache {
      cache.q['url'].do{|url|
        url.R(cache.env).remoteNode
      } || [200, {'Content-Type' => 'text/html'}, ['<form method="GET"><input name="url" autofocus></form>']]}
=end

    PathGET['/generate_204'] = -> _ {Response_204}

    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

    # Amazon
    HostGET['www.amazon.com'] = -> r {
      if r.parts.member?('dp') || r.parts.member?('gp')
        r.remoteNode
      else
        r.deny
      end
    }

    # BizJournal
    HostGET['media.bizj.us'] = -> r {
      if r.path.match? /\*/
        [301, {'Location' => r.path.split(/\*[^.]+\./).join('.')}, []]
      else
        r.remoteNode
      end}
    # Brightcove
    '//edge.api.brightcove.com'.R.HTTPthru

    # Broadcastify
    HostPOST['www.broadcastify.com'] = -> r {r.POSTthru}

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
    HostGET['www.facebook.com'] = -> zuck {
      if zuck.ext == 'php'
        zuck.deny
      else
        zuck.remoteNode
      end}
    HostGET['l.facebook.com']  = -> r {[302, {'Location' => r.q['u']},   []]}
    PathGET['/safe_image.php'] = -> r {[301, {'Location' => r.q['url']}, []]}

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
    %w{feedproxy.google.com gmail.com google.com maps.google.com}.map{|h|HostGET[h] = -> r {r.cachedRedirect}}
    HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        r.remoteNode
      when 'amp'
        r.cachedRedirect
      when 'search'
        r.remoteNode
      when 'url'
        [301, {'Location' => ( r.q['url'] || r.q['q'] )}, []]
      else
        r.remoteFile
      end}
    # %w{accounts mail news play www}.map{|_| "//#{_}.google.com".R.HTTPthru}

    # Imgur
    HostGET['imgur.com'] = HostGET['i.imgur.com'] = -> re {
      if !re.ext.empty? # has extension?
        if 'i.imgur.com' == re.host # has image-host?
          re.remoteFile true # return image
        else # redirect to image-host
          [301,{'Location' => 'https://i.imgur.com' + re.path},[]]
        end
      else # redirect to unwrapped image
        UnwrapImage[re]
      end}

    # Instagram
    HostGET['instagram.com'] = -> r {[301, {'Location' =>  "https://www.instagram.com" + r.path},[]]}
    HostGET['l.instagram.com'] = -> r {[301,{'Location' => r.q['u']},[]]}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # QRZ
    HostGET['qrz.com'] = -> r { r.ext == 'gif' ? r.deny : r.remoteNode }

    # Reddit
    HostGET['i.reddit.com'] = HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[301,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Reuters
    HostGET['s1.reutersmedia.net'] = HostGET['s2.reutersmedia.net'] = HostGET['s3.reutersmedia.net'] = -> r {
      if r.q.has_key? 'w'
        q = r.q ; q.delete 'w'
        [301, {'Location' => r.path + (HTTP.qs q)}, []]
      else
        r.remoteNode
      end}

    # SoundCloud
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
    '//api.twitter.com'.R.HTTPthru
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

  end
end
