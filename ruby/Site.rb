class WebResource
  module HTTP
    # JS CDN - allow scripts unless explicitly dropped
    HostGET['cdnjs.cloudflare.com'] = HostGET['ajax.googleapis.com'] = HostGET['ssl.gstatic.com'] = HostGET['www.gstatic.com'] = HostGET['maps.google.com'] = HostGET['maps.googleapis.com'] = -> r {
      if r.env.has_key?('HTTP_TYPE') && r.env['HTTP_TYPE'].match?(/drop/)
        r.deny
      else
        r.remoteNode
      end}

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
      if %w{ajax api connect plugins si tr}.member?(z.parts[0]) || z.path.match?(/reaction/) || z.ext == 'php'
        z.deny
      else
        z.remoteNode
      end}
    HostGET['graph.facebook.com']  = -> r {r.remoteNode}
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
    HostGET['www.patriotledger.com'] = HostGET['www.providencejournal.com'] = -> r {
      if r.parts[0] == 'storyimage' && r.path.match?(/&/)
        [301, {'Location' => r.path.split('&')[0]},[]]
      else
        r.remote
      end
    }

    # Google
    HostGET['connectivitycheck.gstatic.com'] = -> r {
      if r.path.match? /204$/
        [204, {'Content-Length' => 0}, []]
      else
        r.deny
      end}

    HostGET['google.com'] = HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when /^(maps|recaptcha|s|search|x?js)$/
        r.remoteNode
      when /204$/
        [204, {'Content-Length' => 0}, []]
      when 'url'
        [301, {'Location' => ( r.q['url'] || r.q['q'] )}, []]
      when 'search'
        if ENV.has_key? 'https_proxy' # send to DDG to avoid google blackhole
          [301, {'Location' => 'https://duckduckgo.com/' + r.qs}, []]
        else
          r.remoteNode
        end
      else
        r.remoteFiltered
      end}

    HostGET['www.googleadservices.com'] = -> r {
      if goto = r.q['adurl']
        [301, {'Location' => goto}, []]
      else
        r.deny
      end}

    HostPOST['www.google.com'] = -> r {
      case r.parts[0]
      when 'recaptcha'
        r.POSTthru
      else
        r.env[:deny] = true
        [202,{},[]]
      end}

    %w{drive groups images maps news patents}.map{|prod|
      HostGET[prod+'.google.com'] = -> r { r.remoteNode }}

    %w{groups}.map{|p|
      HostOPTIONS[p+'.google.com'] = -> r { r.OPTIONSthru }
      HostPOST[p+'.google.com'] = -> r { r.POSTthru }}

    # Mail.ru
    HostGET['img.imgsmail.ru'] = -> r {r.remoteNode}

    # Medium
    HostGET['medium.com'] = -> r {
      if %w{_ p}.member? r.parts[0]
        r.deny
      elsif r.q.has_key? 'redirecturl'
        [301, {'Location' => r.q['redirecturl']}, []]
      else
        r.remote
      end}

    # MFC
    HostPOST['www.myfreecams.com'] = -> r {r.POSTthru}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # QRZ
    HostGET['qrz.com'] = HostGET['forums.qrz.com'] = -> r { r.ext == 'gif' ? r.deny : r.remote }

    # Redfin
    HostGET['www.redfin.com'] = -> r { %w{rift stingray}.member?(r.parts[0]) ? r.deny : r.remoteNode }

    # Reuters
    HostGET['s1.reutersmedia.net'] = HostGET['s2.reutersmedia.net'] = HostGET['s3.reutersmedia.net'] = HostGET['s4.reutersmedia.net'] = -> r {
      if r.q.has_key? 'w'
        q = r.q ; q.delete 'w'
        [301, {'Location' => r.path + (HTTP.qs q)}, []]
      else
        r.remoteFiltered
      end}

    # SoundCloud
    HostGET['exit.sc'] = HostGET['w.soundcloud.com'] = -> r {
      url = r.q['url']
      url = '//' + url unless url.match? /^(http|\/)/
      [301, {'Location' => url},[]]}

    # Symantec
    HostGET['clicktime.symantec.com'] = -> r {[301, {'Location' => r.q['u']},[]]}

    # T-Mobile
    HostGET['lookup.t-mobile.com'] = -> re {[200, {'Content-Type' => 'text/html'}, [re.htmlDocument({re.uri => {'dest' => re.q['origurl'].R}})]]}

    # Twitter
    HostOPTIONS['api.twitter.com'] = -> r {r.OPTIONSthru}
    HostPOST['api.twitter.com'] = -> r {r.POSTthru}

    HostGET['t.co'] = -> r {
      if %w{i}.member? r.parts[0]
        r.deny
      else
        r.remoteNode
      end}

    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter, Link => []}}
        '/twitter'.R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}
        [200, {'Content-Type' => 'text/html'}, [re.htmlDocument(graph)]]
      else
        re.ext == 'js' ? re.deny : re.remoteNode
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
    #HostGET['accounts.youtube.com'] = -> r { r.remoteNode }

    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode || %w{browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat playlist user results signin watch watch_videos yts}.member?(mode)
        r.remoteNode
      elsif mode == 'redirect'
        [301, {'Location' =>  r.q['q']},[]]
      elsif mode.match? /204$/
        [204, {'Content-Length' => 0}, []]
      else
        r.drop
      end}

    HostGET['youtu.be'] = HostGET['y2u.be'] = -> re {[301,{'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]},[]]}

  end
  module Webize

    # Twitter
    def tweets
      Nokogiri::HTML.parse(readFile).css('div.tweet').map{|tweet|
        s = Twitter + tweet.css('.js-permalink').attr('href')
        authorName = tweet.css('.username b')[0].inner_text
        author = (Twitter + '/' + authorName).R
        ts = Time.at(tweet.css('[data-time]')[0].attr('data-time').to_i).iso8601
        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, Twitter.R
        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'tweetedlink'+rand.to_s.sha2)
            a.set_attribute('href', Twitter + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
        end
        tweet.css('img').map{|img|
          yield s, Image, img.attr('src').to_s.R}}
    end
    TriplrHTML['twitter.com'] = :tweets

    IndexHTML['twitter.com'] = -> page { graph = {}; posts = []
      # collect triples
      page.tweets{|s,p,o|
        graph[s] ||= {'uri'=>s}
        graph[s][p] ||= []
        graph[s][p].push o}
      # link to timeline
      graph.map{|u,r|
        r[Date].do{|t|
          # mint timeline-entry identifier
          slug = (u.sub(/https?/,'.').gsub(/\W/,'.')).gsub /\.+/,'.'
          time = t[0].to_s.gsub(/[-T]/,'/').sub(':','/').sub /(.00.00|Z)$/, ''
          doc = "/#{time}#{slug}.e".R
          # store tweet
          if !doc.e
            doc.writeFile({u => r}.to_json)
            posts << doc
          end}}
      posts} # indexed tweets

  end
end
