class WebResource
  module HTTP
    DesktopMode = /(alibaba|google|soundcloud|twitter|youtube).com$/
    POSThosts = /(\.(edu|gov)|(anvato|api\.(brightcove|twitter)|(android.*|drive|groups|images|mail|www)\.google|(android|youtubei?).googleapis|reddit|youtube|zillow)\.(com|net))$/

    def sitePOST
      case host
      when 'www.google.com'
        if path.match? /recaptcha|searchbyimage/
          self.POSTthru
        else
          denyPOST
        end
      when /youtube.com$/
        if parts.member? 'stats'
          denyPOST
        elsif env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|subscribe/
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

    # upstream user-interface
    UI = {
      'duckduckgo.com' => true,
      'www.ebay.com' => true,
      's.ytimg.com' => true,
      'www.instagram.com' => true,
      'soundcloud.com' => true,
      'sourceforge.net' => true,
      'www.zillow.com' => true,
      'www.youtube.com' => true,
    }

    # read music blogs
    PathGET['/mu'] = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'},[]]}

    # CDNs
    # allow scripts
    HostGET['ajax.googleapis.com'] = HostGET['cdnjs.cloudflare.com'] = HostGET['s.yimg.com'] = -> r {r.fetch}
    # filter scripts
    HostGET['storage.googleapis.com'] = -> r {r.filter}

    # Reddit
    HostGET['www.reddit.com'] = -> r {
      if r.path == '/'
        [200, {'Content-Type' => 'text/html'}, [r.htmlDocument({'/' => {'uri' => '/', Link => r.subscriptions.map{|sub|('https://www.reddit.com/r/' + sub).R}},
                                                             '/new' => {'uri' => '/new', Title => 'new posts'}})]]
      elsif r.path == '/new'
        r.graphResponse r.twits.map(&:fetch).flatten
      else
        r.remote
      end}

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

    # YouTube
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode || %w{browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat playlist user results signin watch watch_videos yts}.member?(mode)
        r.fetch
      elsif mode == 'redirect'
        [301, {'Location' =>  r.q['q']},[]]
      else
        r.drop
      end}

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
