class WebResource
  module Feed

    def subscribableSite?
      case host
      when /\.reddit.com$/
        parts[0] == 'r'
      when /twitter.com$/
        parts.size > 0 && !%w{new search}.member?(parts[0])
      else
        false
      end
    end

    def subscriptionFile slug=nil
      (case host
       when /reddit.com$/
         '/www.reddit.com/r/' + (slug || parts[1]) + '/.sub'
       when /^twitter.com$/
         '/twitter.com/' + (slug || parts[0]) + '/.following'
       else
         '/' + [host, *parts, '.subscribed'].join('/')
       end).R
    end

  end
  module HTTP

    DesktopUA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3805.0 Safari/537.36'
    TrackHost = /\.(bandcamp|soundcloud|theplatform|track-blaster)\.com$/
    POSThost = /(^www.facebook.com|\.(edu|gov)|(^|\.)(anvato|brightcove|(accounts|android.*|clients?[0-9]*|drive|groups|images|mail|maps|photos|www|youtubei?)\.google(apis)?|reddit|youtube|zillow)\.(com|net))$/
    POSTpath = /^\/_Incapsula_Resource$/

    # POST handling. allow via regex above and define custom handler if needed
    def sitePOST
      case host
      when 'www.facebook.com'
        if %w{/api/graphql/}.member? path
          self.POSTthru
        else
          denyPOST
        end
      when /\.google\.com$/
        if path.match? /searchbyimage|signin/
          self.POSTthru
        else
          denyPOST
        end
      when /\.youtube.com$/
        if parts.member? 'stats'
          denyPOST
        elsif env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/
          self.POSTthru
        else
          denyPOST
        end
      when 'youtubei.googleapis.com'
        if path.match? /\/log/
          denyPOST
        else
          self.POSTthru
        end
      else
        self.POSTthru
      end
    end

    #  music news
    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

    # CDNs
    #  allow scripts
    HostGET['ajax.googleapis.com'] = HostGET['cdnjs.cloudflare.com'] = HostGET['maps.googleapis.com'] = -> r {r.fetch}
    #  filter scripts
    HostGET['storage.googleapis.com'] = -> r {r.filter}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.drop : r.remote}

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {%w{connect pages_reaction_units plugins security tr}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['l.instagram.com'] = -> r {[301, {'Location' =>  r.q['u']},[]]}

    # Google
    PathGET['/url'] = -> r { [301, {'Location' => (r.q['url']||r.q['q'])}, []]}
    HostGET['google.com'] = HostGET['www.google.com'] = -> r {%w{complete js jsapi recaptcha searchdomaincheck}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['www.googleadservices.com'] = -> r {r.q.has_key?('adurl') ? [301, {'Location' =>  r.q['adurl']},[]] : r.remote}
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode || %w{browse_ajax c channel guide_ajax heartbeat iframe_api live_chat playlist user signin watch watch_videos}.member?(mode)
        r.fetch
      elsif mode == 'attribution_link'
        [301, {'Location' =>  r.q['u']}, []]
      elsif %w{embed feed get_video_info results yts}.member? mode
        r.env['HTTP_USER_AGENT'] = DesktopUA
        r.fetch
      elsif mode == 'redirect'
        [301, {'Location' =>  r.q['q']},[]]
      else
        r.drop
      end}

    # Reddit
    HostGET['reddit.com'] = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    HostGET['www.reddit.com'] = -> r {
      if r.path == '/'
        [200, {'Content-Type' => 'text/html'}, [r.htmlDocument({'/' => {'uri' => '/', Link => r.subscriptions.map{|sub|('https://www.reddit.com/r/' + sub).R}},
                                                             '/new' => {'uri' => '/new', Title => 'new posts'}})]]
      elsif r.path == '/new'
        ('//www.reddit.com/r/' + r.subscriptions.join('+') + '/new').R(r.env).fetch
      else
        r.remote
      end}

    # Soundcloud
    HostGET['gate.sc'] = -> r {[301, {'Location' =>  r.q['url']},[]]}

    # Twitter
    HostGET['twitter.com'] = -> r {
      if r.path == '/'
        [200, {'Content-Type' => 'text/html'}, [r.htmlDocument({'/' => {'uri' => '/', Link => r.subscriptions.map{|user|(Twitter + '/' + user).R}},
                                                             '/new' => {'uri' => '/new', Title => 'new posts'}})]]
      elsif r.path == '/new'
        sources = []
        r.subscriptions.shuffle.each_slice(18){|s|
          sources << (Twitter + '/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u}.intersperse('+OR+').join).R }
        r.graphResponse sources.map(&:fetch).flatten
      else
        r.remote
      end}

  end
  module Webize

    # emit tweets from HTML file
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

    def youtube
      if env['REQUEST_PATH'] == '/watch'
        s = 'https://www.youtube.com' + env['REQUEST_URI']
        yield s, Video, s.R
      end
    end

    TriplrHTML['twitter.com'] = :tweets
    TriplrHTML['www.youtube.com'] = :youtube

    IndexHTML['twitter.com'] = -> page {
      graph = {}
      posts = []
      # collect triples
      page.tweets{|s,p,o|
        graph[s] ||= {'uri'=>s}
        graph[s][p] ||= []
        graph[s][p].push o.class == WebResource ? {'uri' => o.uri} : o}
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
      posts }

  end
end
