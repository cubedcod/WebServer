class WebResource
  module HTTP

    # Adobe
    '//sp.auth.adobe.com'.R.HTTPthru

    # Amazon
    HostGET['www.amazon.com'] = -> r {
      if %w{gp}.member? r.parts[0]
        r.deny
      else
        r.remote
      end}

    # Anvato
    '//tkx2-prod.anvato.net'.R.HTTPthru
    '//tkx.apis.anvato.net'.R.HTTPthru

    # BizJournal
    HostGET['media.bizj.us'] = -> r {
      if r.path.match? /\*/
        [301, {'Location' => r.path.split(/\*[^.]+\./).join('.')}, []]
      else
        r.remote
      end}

    # BusinessWire
    HostGET['cts.businesswire.com'] = -> r {
      if r.q.has_key? 'url'
        [301, {'Location' => r.q['url']}, []]
      else
        r.remote
      end}

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
        z.remote
      end}
    HostGET['l.facebook.com']  = -> r {[301, {'Location' => r.q['u']},  []]}
    HostGET['l.instagram.com'] = -> r {[301, {'Location' => r.q['u']},  []]}
    PathGET['/safe_image.php'] = -> r {[301, {'Location' => r.q['url']},[]]}

    # Forbes
    HostGET['thumbor.forbes.com'] = -> r {
      if r.parts[0] == 'thumbor'
        [301, {'Location' => 'http' + URI.unescape(r.path.split(/http/)[-1])}, []]
      else
        r.remote
      end}

    # Gatehouse
    HostGET['www.patriotledger.com'] = -> r {
      if r.parts[0] == 'storyimage' && r.path.match?(/&/)
        [301, {'Location' => r.path.split('&')[0]},[]]
      else
        r.remote
      end
    }

    # Google
    %w{books drive images photos maps news}.map{|prod| HostGET[prod + '.google.com'] = -> r {r.remoteNode}}
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
      elsif r.q.has_key? 'redirecturl'
        [301, {'Location' => r.q['redirecturl']}, []]
      else
        r.remote
      end}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # NYTimes
    #'//samizdat-graphql.nytimes.com'.R.HTTPthru

    # QRZ
    HostGET['qrz.com'] = HostGET['forums.qrz.com'] = -> r { r.ext == 'gif' ? r.deny : r.remote }

    # Reddit
    HostGET['i.reddit.com'] = HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[301,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Redfin
    HostGET['www.redfin.com'] = -> r { %w{rift stingray}.member?(r.parts[0]) ? r.deny : r.remoteNode }

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
        r.remote
      end}

    # WGBH
    HostGET['wgbh.brightspotcdn.com'] = -> r {r.q.has_key?('url') ? [301, {'Location' => r.q['url']}, []] : r.remoteNode}

    # YouTube
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
        [204, {'Content-Length' => 0}, []]
      else
        r.deny
      end}
    #'//www.youtube.com'.R.HTTPthru

  end
end
