class WebResource
  module URIs

    # use sharded-hash path structure, ignore upstream path arrangement
    FlatMap = %w{
a.thumbs.redditmedia.com
b.thumbs.redditmedia.com
i.redd.it
mail.google.com
maps.google.com
www.google.com
www.gstatic.com
www.rfa.org
}

    InsecureShorteners = %w{
bhne.ws
bos.gl
f-st.co
huffp.st
ow.ly
rss.cnn.com
w.bos.gl
}

    UpstreamFormat = %w{
api-v2.soundcloud.com
bandcamp.com
mail.google.com
s.ytimg.com
soundcloud.com
www.instagram.com
www.google.com
www.youtube.com
}
    UpstreamToggle = {}

  end
  module HTTP

    def amp
      [302, {'Location' => 'https://' + (host.split('.') - %w{amp}).join('.') + (path.split('/') - %w{amp amphtml}).join('/')}, []]
    end

    # toggle upstream-UI preference
    PathGET['/go-direct'] = -> r {
      r.q['u'].do{|u|
        UpstreamToggle[u.R.host] = true; [302, {'Location' => u}, []]
      } || r.notfound }
    PathGET['/go-indirect'] = -> r {
      r.q['u'].do{|u|
        UpstreamToggle.delete u.R.host; [302, {'Location' => u}, []]
      } || r.notfound }

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
      } || [200, {'Content-Type' => 'text/html'}, ['<form method="GET"><input name="url" autofocus></form>']] }

    # Discourse
    PathGET['/clicks/track'] = -> r {[302,{'Location' => r.q['url']},[]]}

    # DuckDuckGo
    ['',0,1,2,3,4].map{|n|
      HostGET['proxy'+n.to_s+'.duckduckgo.com'] = -> re {
        case re.parts[0]
        when 'iu'
          [302,{'Location' => re.q['u'],
                'Access-Control-Allow-Origin' => '*'
               },[]]
        when 'iur'
          [302,{'Location' => re.q['image_host']},[]]
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
        [302, {'Location' => r.q['mpre']}, []]
      else
        r.deny
      end
    }

    # Embedly
    HostGET['i.embed.ly'] = -> r {
      if r.path == '/1/display/resize'
        [302, {'Location' => r.q['url']}, []]
      else
        r.deny
      end
    }

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {
      case r.parts[0]
      when /campaign|plugin|reaction|security/
        r.deny
      else
        r.remoteNode
      end}
    HostPOST['www.facebook.com'] = -> r {
      if r.path.match? /comment_fetch/
        r.POSTthru
      else
        r.trackPOST
      end}
    HostGET['instagram.com'] = -> r {[302, {'Location' =>  "https://www.instagram.com" + r.path},[]]}
    HostGET['l.instagram.com'] = -> r {[302,{'Location' => r.q['u']},[]]}
    HostGET['www.instagram.com'] = -> r {r.remoteNode}

    # Google
    %w{feedproxy.google.com google.com}.map{|h| HostGET[h] = -> r {r.cachedRedirect}}

    HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        [200, {'Content-Type' => 'text/html'}, ['<form method="GET" action="/search"><input name="q" autofocus></form>']]
      when 'gmail'
        r.cachedRedirect
      when /async|im(ages?|gres)|x?js|logos|maps|search/
        r.remoteNode
      when 'url'
        [302,{'Location' => r.q['url']},[]]
      else
        r.deny
      end}

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

    # Mixcloud
    HostPOST['www.mixcloud.com'] = -> r {
      r.path == '/graphql' ? r.POSTthru : r.trackPOST
    }

    # Reddit
    HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[302,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Souncloud
    HostGET['exit.sc'] = -> r {[302,{'Location' => r.q['url']},[]]}

    # YouTube
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode
        [200, {'Content-Type' => 'text/html'},['<form method="GET" action="/results"><input name="q" autofocus></form>']]
      elsif %w{browse_ajax c channel embed feed get_video_info iframe_api playlist user results signin watch watch_videos yts}.member? mode
        r.remoteNode
      elsif mode == 'redirect'
        [302, {'Location' =>  r.q['q']},[]]
      elsif mode.match? /204$/
        Response_204
      else
        r.deny
      end}

    HostPOST['www.youtube.com'] = -> r {
      if r.path.match? /results|service.*ajax/
        if r.q['signal']&.match? /INVALIDATION|UNSEEN/
          r.trackPOST
        else
          r.POSTthru
        end
      else
        r.trackPOST
      end}

    HostGET['youtu.be'] = HostGET['y2u.be'] = -> re {[302,{'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]},[]]}

    HostGET['m.youtube.com'] = -> r {[302, {'Location' =>  "https://www.youtube.com" + r.path + r.qs},[]]}

    # T-Mobile
    HostGET['lookup.t-mobile.com'] = -> re {[200, {'Content-Type' => 'text/html'}, [re.htmlDocument({re.uri => {'dest' => re.q['origurl'].R}})]]}

    # Twitter
    HostGET['mobile.twitter.com'] = HostGET['www.twitter.com'] = -> r {[302, {'Location' =>  "https://twitter.com" + r.path},[]]}
    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter,
                             Link => []}}

        ConfDir.join('twitter.com.bu').R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}

        [200,{'Content-Type' => 'text/html'},[re.htmlDocument(graph)]]
      else
        re.remoteNode
      end}

    # Yahoo
    HostGET['s.yimg.com'] = -> r {
      path = r.env['REQUEST_URI']

      if u = r.path.match(%r{https?://?(.*jpg)})
        [302, {'Location' =>  "https://" + u[1]},[]]
      elsif path.match?(/\.js$/)
        ('https://s.yimg.com'+path).R.env(r.env).remoteNode
      else
        r.deny
      end
    }

  end
end
