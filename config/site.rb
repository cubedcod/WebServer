# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        '4archive.org' => :Chan,
        '7chan.org' => :Chan,
        '8kun.top' => :Chan,
        'apnews.com' => :AP,
        'archive.4plebs.org' => :Chan,
        'archive.wakarimasen.moe' => :Chan,
        'boards.4chan.org' => :Chan,
        'boards.4channel.org' => :Chan,
        'github.com' => :GitHub,
        'gitter.im' => :GitterHTML,
        'leftypol.org' => :Chan,
        'lobste.rs' => :Lobsters,
        'mlpol.net' => :Chan,
        'news.ycombinator.com' => :HackerNews,
        'spinitron.com' => :Spinitron,
        'universalhub.com' => :UHub,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :InstagramHTML,
        'www.nationalgeographic.com' => :NatGeo,
        'www.nytimes.com' => :NYT,
        'www.qrz.com' => :QRZ,
        'www.scmp.com' => :Apollo,
        'www.thecrimson.com' => :Apollo,
        'www.universalhub.com' => :UHub,
        'www.youtube.com' => :YouTube,
      }
    end
  end
  module JSON
    Triplr = {
      'api.imgur.com' => :Imgur,
      'api.mixcloud.com' => :MixcloudAPI,
      'api.twitter.com' => :TwitterJSON,
      'gitter.im' => :GitterJSON,
      'www.instagram.com' => :InstagramJSON,
      'www.mixcloud.com' => :Mixcloud,
    }
  end
end
class WebResource
  module URIs

    AllowedHeaders = 'authorization, client-id, content-type, device-fp, device-id, x-access-token, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-csrf-token, x-device-id, x-goog-authuser, x-guest-token, x-hostname, x-lib-version, x-locale, x-twitter-active-user, x-twitter-client-language, x-twitter-utcoffset, x-requested-with' # TODO populate from preflight
    AudioHosts = /(^|\.)(bandcamp|(mix|sound)cloud|youtube).com/
    DarkLogo = %w(www.bostonglobe.com www.nytimes.com)
    HostColors = {
      'forum.solidproject.org' => '#7c4dff',
      'i.redd.it' => '#f40',
      'www.instagram.com' => '#fd7',
      't.co' => 'rgba(29,161,242,1.00)',
      'twitter.com' => 'rgba(29,161,242,1.00)',
      'www.reddit.com' => '#f40',
      'www.youtube.com' => '#f00',
      'youtube.com' => '#f00',
    }

    ReFormat = %w(text/html)
    StaticExt = %w(.bin .css .gif .ico .jpeg .jpg .js .m3u8 .m4a .mp3 .mp4 .ogg .opus .png .svg .wav .webm .webp) # long-cached extensions. new version requires new URI

    # site resources

    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteIcon = SiteDir.join('favicon.ico').read
    SiteCSS = SiteDir.join('site.css').read
    CodeCSS = SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
    KillFile = SiteDir.join('killfile').readlines.map &:chomp
    ScriptHosts = SiteDir.join('script_hosts').readlines.map &:chomp

  end
  module HTTP

    # handler lambdas, available for binding to hostnames

    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['u']||r.query_values['q']).R(r.env).href}, []]}

    NoGunk  = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}

    ImgRehost = -> r {
      ps = r.path.split /https?:\/+/
      ps.size > 1 ? [301, {'Location' => ('https://' + ps[-1]).R(r.env).href}, []] : NoGunk[r]}

    NoQuery = -> r {
      if !r.query                         # URL is qs-free, request and strip response qs
        NoGunk[r].yield_self{|s,h,b|      # upstream response
          h.keys.map{|k|                  # strip query in Location header
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                        # response
      else                                # URL has qs, redirect to path
        [302, {'Location' => ['//', r.host, r.path].join.R(r.env).href}, []]
      end}

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : NoGunk[r]
      else
        NoGunk[r]
      end}

    # URL shorteners

    %w(
bit.ly cbsn.ws dlvr.it econ.trib.al
feedproxy.google.com feeds.feedburner.com feeds.reuters.com
hubs.ly okt.to
reut.rs rss.cnn.com rssfeeds.usatoday.com
t.co ti.me tinyurl.com trib.al
w.bos.gl wired.trib.al
).map{|s| GET s, NoQuery}

    %w(
c212.net gate.sc googleweblight.com
l.facebook.com l.instagram.com
).map{|s| GET s, GotoURL}

    GET 'bos.gl', -> r {r.scheme = 'http'; r.fetch}

    GET 'www.amazon.com', NoGunk
    GET 'www.dropbox.com', NoGunk

    GET 'gitter.im', -> r {
      if r.parts[0] == 'api'
        token = r.join('/token').R
        if !r.env.has_key?('x-access-token') && token.node.exist?
          r.env['x-access-token'] = token.node.read
        end
      end
      NoGunk[r]}

    %w(bostonglobe-prod.cdn.arcpublishing.com).map{|host| GET host, Resizer }

    GET 'res.cloudinary.com', ImgRehost
    GET 'abcnews.go.com', NoGunk
    GET 'www.foxnews.com', NoGunk

    GotoAdURL =  -> r {
      if url = (r.query_values || {})['adurl']
        dest = url.R
        dest.query = '' unless url.match? /dest_url/
        [301, {'Location' => dest}, []]
      else
        r.deny
      end}

    GET 'googleads.g.doubleclick.net', GotoAdURL
    GET 'www.googleadservices.com', GotoAdURL

    GET 'google.com', -> r {[301, {'Location' => ['//www.google.com', r.path, '?', r.query].join.R(r.env).href}, []]}

    GET 'www.google.com', -> r {
      case r.parts[0]
      when 'amp'
        r.path.index('/amp/s/') == 0 ? [301, {'Location' => ('https://' + r.path[7..-1]).R(r.env).href}, []] : r.deny
      when /^(images|x?js|maps)$/
        r.env[:scripts] = true
        NoGunk[r]
      when 'search'
        r.fetch
      when 'sorry' # won't let us search - switch to DuckduckGo
        q = r.query_values['continue'].R.query_values['q']
        [301, {'Location' => 'https://html.duckduckgo.com/html/' + HTTP.qs({q: q})}, []]
      when 'url'
        GotoURL[r]
      else
        r.deny
      end}

    GET 'imgur.com', -> r {
      p = r.parts
      case p[0]
      when /^(a|gallery)$/
        [301, {'Location' => "https://api.imgur.com/post/v1/albums/#{p[1]}?client_id=546c25a59c58ad7&include=media%2Cadconfig%2Caccount".R(r.env).href}, []]
      else
        NoGunk[r]
      end}

    GET 'instagram.com', -> r {[301, {'Location' => ['//www.instagram.com', r.path].join.R(r.env).href}, []]}

    GET 'api.mixcloud.com', -> r {r.fetchHTTP format: 'application/json'}
    GET 'mixcloud.com', -> r {[301, {'Location' => ['//www.mixcloud.com', r.path].join.R(r.env).href}, []]}
    GET 'www.mixcloud.com', -> r {
      if !r.path || r.path == '/'
        r.env[:sort] = 'date'
        r.env[:view] = 'table'
        SiteDir.join('mixcloud').readlines.map(&:chomp).map{|chan|
          print "🔊"
          "https://api.mixcloud.com/#{chan}/cloudcasts/".R(r.env).fetchHTTP format: 'application/json', thru: false}
        r.saveRDF.graphResponse
      else
        r.env[:feeds].push "https://api.mixcloud.com/#{r.parts[0]}/cloudcasts/"
        NoGunk[r]
      end}

    GET 'www.msn.com', NoGunk

    GET 'outline.com', -> r {
      if r.parts.size == 1
        (r.join ['/stat1k/', r.parts[0], '.html'].join).R(r.env).fetch
      else
        NoGunk[r]
      end}

    GET 'old.reddit.com', -> r {
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          puts "upstream redirect", head
          [status, head, body]
        else # read page pointer, missing in HEAD and <head> old and new UI and in HEAD and HTML/RSS <body> in new UI
          links = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|link|links << CGI.unescapeHTML(link[0]).R} # find links
          [302, {'Location' => (links.empty? ? r.href : links.sort_by{|r|r.query_values['count'].to_i}[-1]).to_s.sub('old','www')}, []] # goto link with highest count
        end}}

    GET 'www.reddit.com', -> r {
      r.env[:links][:prev] = ['//old.reddit.com', (r.path || '/').sub('.rss',''), '?',r.query].join.R.href # previous-page pointer
      r.env[:sort] ||= 'date'
      r.env[:view] ||= 'table'
      route = r.parts[0]
      if %w(comments r u user).member? route
        r.path += '.rss' unless r.path.index '.rss'
        NoGunk[r]
      elsif %w(favicon.ico gallery).member? route
        NoGunk[r]
      else
        r.deny
      end}

    GotoReddit =  -> r {[301, {'Location' => ('//www.reddit.com' + r.path).R(r.env).href}, []]}
    GET 'teddit.net', GotoReddit
    GET 'np.reddit.com', GotoReddit

    GET 's4.reutersmedia.net', -> r {
      args = r.query_values || {}
      if args.has_key? 'w'
        args.delete 'w'
        [301, {'Location' => (qs args)}, []]
      else
        NoGunk[r]
      end}

    GET 'cdn.shortpixel.ai', ImgRehost

    GET 'soundcloud.com', -> r {
      if !r.path || r.path == '/'
        r.env[:sort] = 'date'
        r.env[:view] = 'table'
        SiteDir.join('soundcloud').readlines.map(&:chomp).map{|chan|
          print "🔊"
          "https://api-v2.soundcloud.com/stream/users/#{chan}?limit=20&client_id=vFImNkLVyrDxqzOjhw0lL0ZPUsf4KfEo".R(r.env).fetchHTTP thru: false}
        r.saveRDF.graphResponse
      else
       NoGunk[r]
      end}

    GET 'go.theregister.com', -> r {
      if r.parts[0] == 'feed'
        [301, {'Location' => 'https://' + r.path[6..-1]}, []]
      else
        r.deny
      end}

    GotoTwitter = -> r {[301, {'Location' => ('//twitter.com' + r.path).R(r.env).href}, []]}

    Twitter = -> r {
      r.env[:sort] = 'date'
      r.env[:view] = 'table'
      parts = r.parts
      qs = r.query_values || {}
      cursor = qs.has_key?('cursor') ? ('&cursor=' + qs['cursor']) : ''

      if r.env['HTTP_COOKIE'] # auth headers
        attrs = {}
        r.env['HTTP_COOKIE'].split(';').map{|attr|
          k, v = attr.split('=').map &:strip
          attrs[k] = v}
        r.env['authorization'] ||= 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
        r.env['x-csrf-token'] ||= attrs['ct0'] if attrs['ct0']
        r.env['x-guest-token'] ||= attrs['gt'] if attrs['gt']
      end

      searchURL = -> q {
        ('https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_ext_alt_text=true&include_quote_count=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweet=true&q='+q+'&tweet_search_mode=live&count=20' + cursor + '&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2ChighlightedLabel').R(r.env)}

      (if !r.path || r.path == '/'                                                                                  # feed
       SiteDir.join('twitter').readlines.map(&:chomp).shuffle.each_slice(18){|t|
         print '🐦'
         searchURL[t.map{|u|'from%3A'+u}.join('%2BOR%2B')].fetchHTTP thru: false}
       r.saveRDF.graphResponse
      elsif parts.size == 1 && !%w(favicon.ico manifest.json push_service_worker.js search sw.js).member?(parts[0]) # user page
        if qs.has_key? 'q' # [q]uery local tweet-cache
          r.cacheResponse
        elsif qs.has_key? 'ref_src'
          [301, {'Location' => r.path}, []]
        else # find uid, show tweets and profile data
          uid = nil
          uidQuery = "https://twitter.com/i/api/graphql/Vf8si2dfZ1zmah8ePYPjDQ/UserByScreenNameWithoutResults?variables=%7B%22screen_name%22:%22#{parts[0]}%22%2C%22withHighlightedLabel%22:true%7D"
          URI.open(uidQuery, r.headers){|response|
            body = response.read
            if response.meta['content-type'].index 'json'
              json = ::JSON.parse HTTP.decompress({'Content-Encoding' => response.meta['content-encoding']}, body)
              if json['data'].empty?
                r.notfound
              else
                user = json['data']['user']['legacy']
                uid = json['data']['user']['rest_id']
                r.env[:repository] ||= RDF::Repository.new # RDF storage for profile triples
                r.env[:repository] << RDF::Statement.new(r, Abstract.R, user['description'].hrefs)
                r.env[:repository] << RDF::Statement.new(r, Date.R, user['created_at'])
                r.env[:repository] << RDF::Statement.new(r, Title.R, user['name'])
                r.env[:repository] << RDF::Statement.new(r, (Schema+'location').R, user['location'])
                %w(profile_banner_url profile_image_url_https).map{|i|
                  if image = user[i]
                    r.env[:repository] << RDF::Statement.new(r, Image.R, image.R)
                  end}
                ('https://api.twitter.com/2/timeline/profile/' + uid + '.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&include_tweet_replies=false&userId=' + uid + '&count=20' + cursor + '&ext=mediaStats%2CcameraMoment').R(r.env).fetch
              end
            else
              [200, response.meta, [body]]
            end}
        end
      elsif parts.member?('status') || parts.member?('statuses')                                                    # tweet / conversation page
        if parts.size == 2
          r.cacheResponse # search local archive
        else
          convo = parts.find{|p| p.match? /^\d{8}\d+$/ }
          "https://api.twitter.com/2/timeline/conversation/#{convo}.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&count=20#{cursor}&ext=mediaStats%2CcameraMoment".R(r.env).fetch
        end
      elsif parts[0] == 'hashtag'                                                                                   # hashtag search
        searchURL['%23'+parts[1]].fetch
      elsif parts[0] == 'search'                                                                                    # search
        qs.has_key?('q') ?  searchURL[qs['q']].fetch : r.notfound
      else
        NoGunk[r]
       end).yield_self{|s,h,b|
        if [401,403,429].member? s
          r.env[:notransform] = true
          %w(HTTP_COOKIE authorization x-csrf-token x-guest-token).map{|a| r.env.delete a }
          r.fetch
        else
          [s,h,b]
        end}}

    GET 'nitter.snopyta.org', GotoTwitter
    GET 'twitter.com', Twitter
    GET 'mobile.twitter.com', Twitter

    GET 'www.walmart.com', NoGunk

    GET 'finance.yahoo.com', NoGunk
    GET 'news.yahoo.com', NoGunk
    GET 's.yimg.com', ImgRehost

    GotoYT = -> r {[301, {'Location' => ['//www.youtube.com', r.path, '?', r.query].join.R(r.env).href}, []]}
    GET 'm.youtube.com', GotoYT
    GET 'yewtu.be', GotoYT
    GET 'youtube.com', GotoYT

    GET 'www.youtube.com', -> r {
      path = r.parts[0]
      qs = r.query_values || {}
      if %w{attribution_link redirect}.member? path
        [301, {'Location' => qs['q'] || qs['u']}, []]
      elsif path == 's'
        if r.path.match? /annot|endscreen|prepopulat|remote|tamper/
          r.deny
        else
          r.fetch
        end
      elsif %w(browse_ajax c channel embed feed feeds generate_204 get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist results user watch watch_videos yts).member?(path) || !path
        case path
        when /ajax|embed/
          r.env[:notransform] = true
          r.fetch.yield_self{|s,h,b|
            if h['Content-Type']&.index('html')
              doc = Nokogiri::HTML.parse b[0]
              edited = false
              doc.css('script').map{|s|
                js = /\/\/www.google.com\/js\//
                if s.inner_text.match? js
                  edited = true
                  s.content = s.inner_text.gsub(js,'#')
                end
                puts s.inner_text}
              if edited
                b = [doc.to_html]
                h.delete 'Content-Length'
              end
            end
            [s,h,b]}
        when 'get_video_info'
          if r.query_values['el'] == 'adunit' # TODO customised ad insertion
            [200, {"Access-Control-Allow-Origin"=>"https://www.youtube.com", "Content-Type"=>"application/x-www-form-urlencoded", "Content-Length"=>"0"}, ['']]
          else
            r.env[:notransform] = true
            r.fetch.yield_self{|s,h,b|
              puts h, Rack::Utils.parse_query(b[0])
              [s,h,b]}
          end
        else
          NoGunk[r]
        end
      else
        r.deny
      end}
  end

  def Apollo doc, &b
    JSONembed doc, /window[^{]+Apollo[^{]+{/i, &b
  end

  def AP doc
    doc.css('script').map{|script|
      script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data| # find the JSON
        data = data[0]
        data = data[0..-2] if data[-1] == ';'
        Webize::JSON::Reader.new(data, base_uri: self).scanContent do |s,p,o| # call JSON triplr
          if p == 'gcsBaseUrl' # bind image URL
            p = Image
            o += '2000.jpeg'
          end
          yield s,p,o
        end}}
  end

  def CityData doc
    doc.css("table[id^='post']").map{|post|
      subject = join '#' + post['id']
      yield subject, Type, Post.R
      post.css('a.bigusername').map{|user|
        yield subject, Creator, (join user['href'])
        yield subject, Creator, user.inner_text }
      if headers = post.css('td.thead > div.normal')
        if datetime = headers[1]
          datetime = datetime.inner_text.strip
          date, timeAP = datetime.split ','
          if %w{Today Yesterday}.member? date
            dt = Time.now
            dt = dt.yesterday if date == 'Yesterday'
            year = dt.year
            month = dt.month
            day = dt.day
          else
            month, day, year = date.split('-').map &:to_i
          end
          time, ampm = timeAP.strip.split ' '
          hour, min = time.split(':').map &:to_i
          hour = hour.to_i
          pm = ampm == 'PM'
          hour += 12 if pm
          yield subject, Date, "#{year}-#{'%02d' % month}-#{'%02d' % day}T#{'%02d' % hour}:#{'%02d' % min}:00+00:00"
        end
      end
      post.css("div[id^='post_message']").map{|content|
        yield subject, Content, Webize::HTML.format(content, self)}
      post.remove }
    ['#fixed_sidebar'].map{|s|doc.css(s).map &:remove}
  end

  def GitHub doc
    if title = doc.css('.gh-header-title')[0]
      yield self, Title, title.inner_text
      title.remove
    end
    
    if meta = doc.css('.gh-header-meta')[0]
      if author = meta.css('author[href]')[0]
        yield self, Creator, author['href'].R
      end
      meta.css('[datetime]').map{|date| yield self, Date, date['datetime'] }
      yield self, Content, meta.inner_text
      meta.remove
    end

    doc.css('.Box-row, .TimelineItem').map{|item|
      timestamp = item.css('.js-timestamp')[0]
      subject = join((timestamp && timestamp['href']) || item['href'] || ('#' + (item['id'] || (Digest::SHA2.hexdigest item.to_s))))
      yield subject, Type, Post.R

      item.css("div[role='rowheader'] a, [data-hovercard-type='issue']").map{|title|
        yield subject, Title, title.inner_text
        yield subject, Link, join(title['href'])
        title.remove}

      if time = item.css('[datetime]')[0]
        yield subject, Date, time['datetime']
      end

      if author = item.css('.author, .opened-by > a')[0]
        yield subject, Creator, join(author['href'])
        yield subject, Creator, author.inner_text
      end

      yield subject, To, self
      yield subject, Content, Webize::HTML.format((item.css('.comment-body')[0] || item), self)

      item.remove
    }
  end

  def GitterHTML doc
    doc.css('script').map{|script|
      text = script.inner_text
      if text.match? /^window.gitterClientEnv/     # environment JSON
        if token = text.match(/accessToken":"([^"]+)/)
          token = token[1]
          tFile = join('/token').R
          unless tFile.node.exist? && tFile.node.read == token
            tFile.writeFile token                  # save updated client-token
            puts ['🎫 ', host, token].join ' '
          end
        end
        if room = text.match(/"id":"([^"]+)/)
          room_id = room[1]                         # room id
          room = ('http://gitter.im/api/v1/rooms/' + room_id).R # room URI
          env[:links][:prev] = room.uri + '/chatMessages?lookups%5B%5D=user&includeThreads=false&limit=31'
          yield room, Schema + 'sameAs', self, room # link room (integer) id to URI
          yield room, Type, (SIOC + 'ChatChannel').R
        end
      end}

    # messages
    messageCount = 0
    doc.css('.chat-item').map{|msg|
      id = msg.classes.grep(/^model-id/)[0].split('-')[-1] # find ID
      subject = 'http://gitter.im' + path + '?at=' + id   # subject URI
      yield subject, Type, Post.R
      if from = msg.css('.chat-item__from')[0]
        yield subject, Creator, from.inner_text
      end
      if username = msg.css('.chat-item__username')[0]
        yield subject, Creator, ('https://github.com/' + username.inner_text.sub(/^@/,'')).R
      end
      if image = msg.css('.avatar__image')[0]
        yield subject, Image, image['src'].R
      end
      yield subject, Date, '%03d' % messageCount += 1
      yield subject, Content, (Webize::HTML.format msg.css('.chat-item__text')[0], self)
      msg.remove }
    doc.css('header').map &:remove
  end

  def GitterJSON tree, &b
    return if tree.class == Array
    return unless items = tree['items']
    items.map{|item|
      id = item['id']                              # message identifier
      room_id = parts[3]                           # room identifier
      room = ('http://gitter.im/api/v1/rooms/'  + room_id).R # room URI
      env[:links][:prev] ||= room.uri + '/chatMessages?lookups%5B%5D=user&includeThreads=false&beforeId=' + id + '&limit=31'
      date = item['sent']
      uid = item['fromUser']
      user = tree['lookups']['users'][uid]
      graph = ['/' + date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), 'gitter', user['username'], id].join('.').R # graph on timeline
      subject = 'http://gitter.im' + path + '?at=' + id # subject URI
      yield subject, Date, date, graph
      yield subject, Type, (SIOC + 'MicroblogPost').R, graph
      yield subject, Creator, join(user['url']), graph
      yield subject, Creator, user['displayName'], graph
      yield subject, To, room, graph
      yield subject, Image, user['avatarUrl'], graph
      yield subject, Content, (Webize::HTML.format item['html'], self), graph
    }
  end

  def GoogleHTML doc
    doc.css('div.g').map{|g|
      if r = g.css('a[href]')[0]
        subject = r['href'].R
        if subject.host
          if title = r.css('h3')[0]
            yield subject, Type, (Schema+'SearchResult').R
            yield subject, Title, title.inner_text
            yield subject, Content, Webize::HTML.format(g.inner_html, self)
            if (icon = ('//' + subject.host + '/favicon.ico').R env).node.exist?
              yield subject, Schema+'icon', icon
            end
          end
        end
      end
      g.remove}
    if pagenext = doc.css('#pnnext')[0]
      env[:links][:next] ||= join pagenext['href']
    end
    doc.css('#botstuff, #bottomads, #footcnt, #searchform, svg, #tads').map &:remove
  end

  def HackerNews doc
    base = 'https://news.ycombinator.com/'

    # stories
    doc.css('form, img, .yclinks').map &:remove
    doc.css('a.storylink').map{|story|
      story_row = story.parent.parent
      comments_row = story_row.next_sibling.next_sibling
      if a = comments_row.css('a')[-1]
        if subject = a['href']
          if date = Chronic.parse(comments_row.css('.age > a')[0].inner_text.sub(/^on /,''))
            subject = join subject
            date = date.iso8601
            graph = ['/' + date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:+]/,'.'), (subject.to_s.split(/[:\/?&=]+/) - BasicSlugs)].join('.').R # graph URI
            yield subject, Type, Post.R, graph
            yield subject, Title, story.inner_text, graph
            yield subject, Link, story['href'], graph
            yield subject, Date, date, graph
            story_row.remove
            comments_row.remove
          end
        end
      end}

    # comments
    doc.css('div.comment').map{|comment|
      post = comment.parent
      date = post.css('.age > a')[0]
      graph = subject = base + date['href']
      comment.css('.reply').remove
      if time = Chronic.parse(date.inner_text.sub(/^on /,''))
        time = time.iso8601
        yield subject, Date, time, graph
      end
      yield subject, Type, Post.R, graph
      if user = post.css('.hnuser')[0]
        yield subject, Creator, (base + user['href']).R, graph
        yield subject, Creator, user.inner_text, graph
      end
      yield subject, To, self, graph
      if parent = post.css('.par > a')[0]
        yield subject, To, (base + parent['href']).R, graph
      end
      if story = post.css('.storyon > a')[0]
        yield subject, To, (base + story['href']).R, graph
        yield subject, Title, story.inner_text, graph
      end
      yield subject, Content, (Webize::HTML.format comment, self), graph
      post.remove
    }
  end

  def Imgur tree, &b
    tree['media'].map{|i|
      url = i['url'].R
      yield self, File.extname(url.path) == '.mp4' ? Video : Image, url}
  end

  def InstagramHTML doc, &b
    objvar = /^window._sharedData = /
    doc.css('script').map{|script|
      if script.inner_text.match? objvar
        InstagramJSON ::JSON.parse(script.inner_text.sub(objvar, '')[0..-2]), &b
      end}
  end

  def InstagramJSON tree, &b
    Webize::JSON.scan(tree){|h|
      if tl = h['edge_owner_to_timeline_media']
        end_cursor = tl['page_info']['end_cursor'] rescue nil
        uid = tl["edges"][0]["node"]["owner"]["id"] rescue nil
        env[:links][:prev] ||= 'https://www.instagram.com/graphql/query/' + HTTP.qs({query_hash: :e769aa130647d2354c40ea6a439bfc08, variables: {id: uid, first: 12, after: end_cursor}.to_json}) if uid && end_cursor
      end
      if h['shortcode']
        s = graph = ['https://www.instagram.com/p/', h['shortcode'], '/'].join.R
        yield s, Type, Post.R, graph
        yield s, Image, h['display_url'].R, graph if h['display_url']
        if owner = h['owner']
          yield s, Creator, ('https://www.instagram.com/' + owner['username']).R, graph if owner['username']
          yield s, To, 'https://www.instagram.com/'.R, graph
        end
        if time = h['taken_at_timestamp']
          yield s, Date, Time.at(time).iso8601, graph
        end
        if text = h['edge_media_to_caption']['edges'][0]['node']['text']
          yield s, Content, Webize::HTML.format(CGI.escapeHTML(text).split(' ').map{|t|
                                                  if match = (t.match /^@([a-zA-Z0-9._]+)(.*)/)
                                                    "<a class='uri' href='https://www.instagram.com/#{match[1]}'>#{match[1]}</a>#{match[2]}"
                                                  else
                                                    t
                                                  end}.join(' '), self), graph
        end rescue nil
      end}
  end

  def Lobsters doc
    doc.css('.h-entry').map{|entry|
      avatar, author, archive, post = entry.css('.byline a')
      post = archive unless post
      subject = join post['href']
      yield subject, Type, Post.R
      yield subject, Creator, (join author['href'])
      yield subject, Creator, author.inner_text
      yield subject, Image, (join avatar.css('img')[0]['src'])
      yield subject, Date, Time.parse(entry.css('.byline > span[title]')[0]['title']).iso8601
      entry.css('.link > a').map{|link|
        yield subject, Link, (join link['href'])
        yield subject, Title, link.inner_text}
      entry.css('.tags > a').map{|tag|
        yield subject, To, (join tag['href'])
        yield subject, Abstract, tag['title']}

      entry.remove }

    doc.css('div.comment[id]').map{|comment|
      post_id, avatar, author, post_link = comment.css('.byline > a')
      if post_link
        subject = (join post_link['href']).R
        graph = subject.join [subject.basename, subject.fragment].join '.'
        yield subject, Type, Post.R, graph
        yield subject, To, (join subject.path), graph
        yield subject, Creator, (join author['href']), graph
        yield subject, Creator, author.inner_text, graph
        yield subject, Image, (join avatar.css('img')[0]['src']), graph
        yield subject, Date, Time.parse(comment.css('.byline > span[title]')[0]['title']).iso8601, graph
        yield subject, Content, (Webize::HTML.format comment.css('.comment_text')[0], self), graph
      end
      comment.remove }
  end

  def Mixcloud tree, &b
    if data = tree['data']
      if user = data['user']
        if username = user['username']
          if uploads = user['uploads']
            if edges = uploads['edges']
              edges.map{|edge|
                mix = edge['node']
                slug = mix['slug']
                subject = graph = ('https://www.mixcloud.com/' + username + '/' + slug).R
                yield subject, Title, mix['name'], graph
                yield subject, Date, mix['publishDate'], graph
                yield subject, Schema+'duration', mix['audioLength'], graph
                yield subject, Image, ('https://thumbnailer.mixcloud.com/unsafe/1280x1280/' + mix['picture']['urlRoot']).R, graph
                if audio = mix['previewUrl']
                  yield subject, Audio, audio.R, graph
                end
              }
            end
          end
        end
      end
    end
  end

  def MixcloudAPI tree, &b
    yield self, Title, tree['name']
    tree['data'].map{|mix|
      graph = subject = mix['url'].R
      yield subject, Type, Post.R, graph
      yield subject, Title, mix['name'], graph
      yield subject, Date, mix['created_time'], graph
      yield subject, Creator, mix['user']['name'].R,graph
      yield subject, To, mix['user']['url'].R,graph
      mix['pictures'].map{|_,i|
        yield subject, Image, i.R, graph if i.match? /1024x1024/}
      yield subject, Schema+'duration', mix['audio_length'], graph
      mix['tags'].map{|tag|
        yield subject, Abstract, tag['name'], graph}}
    if pages = tree['paging']
      env[:links][:next] = pages['next']
      env[:links][:prev] = pages['previous']
    end
  end

  def NatGeo doc, &b
    JSONembed doc, /window[^{]+NatGeo[^{]+{/i, &b
  end

  def NYT doc, &b
    JSONembed doc, /^window.__preload/, &b
  end

  def QRZ doc, &b
    doc.css('script').map{|script|
      script.inner_text.scan(%r(biodata'\).html\(\s*Base64.decode\("([^"]+))xi){|data|
        yield self, Content, Base64.decode64(data[0]).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')}}
  end

  def Spinitron doc
    if show = doc.css('.show-title > a')[0]
      show_name = show.inner_text
      show_url = join show['href']
      station = show_url.R.parts[0]
    end

    if dj = doc.css('.dj-name > a')[0]
      dj_name = dj.inner_text
      dj_url = join dj['href']
    end

    if timeslot = doc.css('.timeslot')[0]
      day = timeslot.inner_text.split(' ')[0..2].join(' ') + ' '
    end

    doc.css('.spin-item').map{|spin|
      spintime = spin.css('.spin-time > a')[0]
      date = Chronic.parse(day + spintime.inner_text).iso8601
      subject = join spintime['href']
      graph = ['/' + date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), station, show_name.split(' ')].join('.').R # graph URI
      data = JSON.parse spin['data-spin']
      yield subject, Type, Post.R, graph
      yield subject, Date, date, graph
      yield subject, Creator, dj_url, graph
      yield subject, Creator, dj_name, graph
      yield subject, To, show_url, graph
      yield subject, To, show_name, graph
      yield subject, Schema+'Artist', data['a'], graph
      yield subject, Schema+'Song', data['s'], graph
      yield subject, Schema+'Release', data['r'], graph
      if year = spin.css('.released')[0]
        yield subject, Schema+'Year', year.inner_text, graph
      end
      spin.css('img').map{|img| yield subject, Image, img['src'].R, graph }
      if note = spin.css('.note')[0]
        yield subject, Content, note.inner_html
      end
      spin.remove }
  end

  def TwitterJSON tree, &b
    return if tree.class == Array
    if objects = tree['globalObjects']
      users = objects['users'] || {}
      (objects['tweets'] || {}).map{|id, tweet|
        id = tweet['id_str']
        uid = tweet['user_id_str']
        userinfo = users[uid] || {}
        username = userinfo['screen_name'] || 'anonymous'
        user = ['https://', env[:base].host, '/', username].join
        uri = user + '/status/' + id
        yield uri, Type, (SIOC + 'MicroblogPost').R
        yield uri, To, 'https://twitter.com'.R
        yield uri, Date, Time.parse(tweet['created_at']).iso8601
        yield uri, Creator, user.R
        yield uri, Creator, userinfo['name']
        yield uri, Content, tweet['full_text'].hrefs
        %w(entities extended_entities).map{|entity_type|
          if entities = tweet[entity_type]
            if media = entities['media']
              media.map{|m|
                case m['type']
                when 'photo'
                  yield uri, Image, m['media_url'].R
                when /animated_gif|video/
                  yield uri, Image, m['media_url'].R
                  if info = m['video_info']
                    if variants = info['variants']
                      variants.map{|variant|
                        yield uri, Video, variant['url'].R if variant['content_type'] == 'video/mp4'
                      }
                    end
                  end
                else
                  puts "media: ", ::JSON.pretty_generate(m)
                end
              }
            end
            if urls = entities['urls']
              urls.map{|url|
                yield uri, Link, url['expanded_url'].R}
            end
          end
        }
      }
    end
    if timeline = tree['timeline']
      if c = timeline['instructions'][0]['addEntries']['entries'].find{|e|e['content'].has_key?('operation') && e['content']['operation']['cursor']['cursorType'] == 'Bottom'}
        env[:links][:prev] = '?cursor=' + c['content']['operation']['cursor']['value']
      end
    end
  end

  def UHub doc
    doc.css('.pager-next > a[href]').map{|n|     env[:links][:next] ||= (join n['href'])}
    doc.css('.pager-previous > a[href]').map{|p| env[:links][:prev] ||= (join p['href'])}
  end

  def YouTube doc, &b
    JSONembed doc, /var ytInitial(Data|PlayerResponse) = /i, &b
  end

end
