class WebResource
  module Feed

    def subscriptionFile slug=nil
      (case host
       when /reddit.com$/
         '/www.reddit.com/r/' + (slug || parts[1]) + '/.sub'
       when /^twitter.com$/
         '/twitter.com/' + (slug || parts[0] || '') + '/.following'
       else
         '/feed/' + [host, *parts].join('.')
       end).R
    end

  end
  module HTTP

    # Agent preferring upstream "desktop" interface
    DesktopUA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3805.0 Safari/537.36'

    # hosts with dirs named 'track'
    TrackHost = /\.(bandcamp|soundcloud|theplatform|track-blaster)\.com$/

    # POSTs, allow in regex and define handler if needed
    POSThost = /(^www.facebook.com|\.(edu|gov)|(^|\.)(anvato|brightcove|(accounts|android.*|clients?[0-9]*|drive|groups|images|mail|maps|photos|www|youtubei?)\.google(apis)?|soundcloud|youtube|zillow)\.(com|net))$/
    POSTpath = /^\/_Incapsula_Resource$/
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
      when /\.soundcloud\.com$/
        if host.match? /^api/
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

    # redirects
    PathGET['/mu']  = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'}, []]} # new posts in bostonmusic blog
    PathGET['/url'] = -> r {[301,{'Location' => (r.q['url'] || r.q['q'])}, []]}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['proxy.duckduckgo.com'] = -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.q['u']}, []] : r.remote}

    # eBay
    HostGET['i.ebayimg.com'] = -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.fetch
      end}

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {%w{connect pages_reaction_units plugins security tr}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['l.instagram.com'] = HostGET['l.facebook.com'] = -> r {[301, {'Location' => r.q['u']},[]]}

    # Google
    (0..3).map{|i|HostGET["encrypted-tbn#{i}.gstatic.com"] = -> r {r.noexec}}
    HostGET['ajax.googleapis.com'] = HostGET['cdnjs.cloudflare.com'] = -> r {r.fetch}     # CDN with mainstream JS libraries, allow
    HostGET['feedproxy.google.com'] = HostGET['storage.googleapis.com'] = -> r {r.noexec} # CDN with mystery JS, filter
    HostGET['feeds.feedburner.com'] = -> r {r.path[1] == '~' ? r.drop : r.noexec}
    HostGET['google.com'] = HostGET['maps.google.com'] = HostGET['maps.googleapis.com'] = HostGET['www.google.com'] = -> req {
      mode = req.parts[0]
      if %w{complete searchdomaincheck}.member? mode
        req.drop
      elsif mode == 'maps'
        req.env['HTTP_USER_AGENT'] = DesktopUA
        req.fetch
      else
        case req.env['HTTP_TYPE']
        when /dropURI/
          req.drop
        else
          req.fetch.do{|status, head, body|
            case status
            when 403 # goog blocked by a middlebox, try DDG
              [302, {'Location' => 'https://duckduckgo.com/' + req.qs}, []]
            else
              [status, head, body]
            end}
        end
      end}
    HostGET['www.googleadservices.com'] = -> r {r.q['adurl'] ? [301, {'Location' => r.q['adurl']},[]] : r.drop}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Reddit
    HostGET['reddit.com'] = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    HostGET['www.reddit.com'] = -> r {
      if r.path == '/'
        ('//www.reddit.com/r/' + r.subscriptions.join('+') + '/new').R(r.env).fetch
      else
        r.remote
      end}

    # Reuters
    (0..5).map{|i|
      HostGET["s#{i}.reutersmedia.net"] = -> r {
        if r.q.has_key? 'w'
          q = r.q
          q.delete 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + (HTTP.qs q)}, []]
        else
          r.noexec
        end}}

    # Soundcloud
    HostGET['gate.sc'] = -> r {[301, {'Location' =>  r.q['url']},[]]}

    # Twitter
    HostGET['twitter.com'] = -> r {
      if !r.path || r.path == '/'
        sources = []
        r.subscriptions.shuffle.each_slice(18){|s|
          sources << (Twitter + '/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u}.intersperse('+OR+').join).R(r.env) }
        r.graphResponse sources.map{|source|
          source.fetch false}.flatten
      else
        r.remote
      end}

    # YouTube
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if %w{browse_ajax c channel guide_ajax heartbeat iframe_api live_chat playlist signin watch_videos}.member? mode
        r.fetch
      elsif !mode || %w{embed feed get_video_info results user watch yts}.member?(mode)
        r.env['HTTP_USER_AGENT'] = DesktopUA
        r.fetch
      elsif %w{attribution_link redirect}.member? mode
        [301, {'Location' =>  r.q['q'] || r.q['u']},[]]
      else
        r.drop
      end}

  end

  def self.twits
    `cd ~/src/WebServer && git show -s --format=%B e015012b8c53e15e460a297b636b03ae853df239`.split.map{|twit|
      (Twitter + '/' + twit).R.subscribe}
  end

  module Webize

    Gunk = %w{
 .featured-headlines
 .global-audio-components
}

    def AP doc
      doc.css('script').map{|script|
        script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data|
          data = data[0]
          data = data[0..-2] if data[-1] == ';'
          json = ::JSON.parse data
          yield env['REQUEST_URI'], Content, HTML.render(HTML.keyval (HTML.webizeHash json), env)}}
    end

    def Google doc
      doc.css('a[aria-label^="Next"]').map{|a|
        env[:links][:next] ||= a['href']
      }
      doc.css('a[href^="/url"]').map{|a|
        if s = (HTTP.parseQs a['href'].R.query)['q']
          yield s, Type, Resource.R
          yield s, Abstract, a.inner_text.gsub(/<[^>]+>/,' ')
          #a.remove
        else
          puts "no URL found:" + a.to_s
        end
      }
    end

    IGgraph = /^window._sharedData = /
    def Instagram doc
      doc.css('script').map{|script|
        if script.inner_text.match? IGgraph
          graph = ::JSON.parse script.inner_text.sub(IGgraph,'')[0..-2]
          HTML.webizeHash(graph){|h|
            if h['shortcode']
              s = 'https://www.instagram.com/p/' + h['shortcode']
              
              yield s, Image, h['display_url'].R if h['display_url']
              h['owner'].do{|o|
                yield s, Creator, ('https://www.instagram.com/' + o['username']).R
                yield s, To, 'https://www.instagram.com/'.R
              }
              h['edge_media_to_caption']['edges'][0]['node']['text'].do{|t|
                yield s, Abstract, CGI.escapeHTML(t)
              } rescue nil

            end
            puts :_________________, ::JSON.pretty_generate(h)
          }
        end}
    end

    def Twitter doc
      %w{grid-tweet tweet}.map{|tweetclass|
      doc.css('.' + tweetclass).map{|tweet|
        s = Twitter + (tweet.css('.js-permalink').attr('href') || tweet.attr('data-permalink-path'))
        authorName = tweet.css('.username b')[0].do{|b|b.inner_text} || s.R.parts[0]
        author = (Twitter + '/' + authorName).R
        ts = (tweet.css('[data-time]')[0].do{|unixtime|
                Time.at(unixtime.attr('data-time').to_i)} || Time.now).iso8601
        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, Twitter.R
        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'link'+rand.to_s.sha2)
            a.set_attribute('href', Twitter + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
        end
        if img = tweet.attr('data-resolved-url-large')
          yield s, Image, img.to_s.R
        end
        tweet.css('img').map{|img|
          yield s, Image, img.attr('src').to_s.R}}}
    end

    def YouTube doc
      if env['REQUEST_PATH'] == '/watch'
        s = 'https://www.youtube.com' + env['REQUEST_URI']
        yield s, Video, s.R
      end
    end

    Triplr[:HTML] = {
      'apnews.com' => :AP,
      'www.apnews.com' => :AP,
      'www.google.com' => :Google,
      'www.instagram.com' => :Instagram,
      'twitter.com' => :Twitter,
      'www.youtube.com' => :YouTube,
    }

  end
end
