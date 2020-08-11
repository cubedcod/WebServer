# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        '8kun.top' => :Chan,
        'apnews.com' => :AP,
        'bunkerchan.xyz' => :Chan,
        'drudgereport.com' => :Drudge,
        'archive.4plebs.org' => :Chan,
        'boards.4chan.org' => :Chan,
        'boards.4channel.org' => :Chan,
        'github.com' => :GitHub,
        'gitter.im' => :GitterHTML,
        'lobste.rs' => :Lobsters,
        'news.ycombinator.com' => :HackerNews,
        'spinitron.com' => :Spinitron,
        'universalhub.com' => :UHub,
        'www.aliexpress.com' => :AX,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :InstagramHTML,
        'www.qrz.com' => :QRZ,
        'www.universalhub.com' => :UHub,
        'www.youtube.com' => :YouTube,
      }
    end
  end
  module JSON
    Triplr = {
      'api.twitter.com' => :TwitterJSON,
      'gitter.im' => :GitterJSON,
      'www.instagram.com' => :InstagramJSON,
    }
  end
end
class WebResource
  module URIs
    AllowedHeaders = 'authorization, client-id, content-type, device-fp, device-id, x-access-token, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-csrf-token, x-device-id, x-goog-authuser, x-guest-token, x-hostname, x-lib-version, x-locale, x-twitter-active-user, x-twitter-client-language, x-twitter-utcoffset, x-requested-with' # TODO populate from preflight

    # local resources
    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteIcon = SiteDir.join('favicon.ico').read
    SiteCSS = SiteDir.join('site.css').read
    CodeCSS = SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read

  end
  module HTTP

    # handler lambdas
    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['u']||r.query_values['q'])}, []]}
    NoGunk  = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}
    NoQuery = -> r {
      if !r.query                         # request
        NoGunk[r].yield_self{|s,h,b|      #  inspect response
          h.keys.map{|k|                  #  strip query from relocation
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                        #  response
      else                                # request has query
        [302, {'Location' => r.path}, []] #  redirect to path
      end}
    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : NoGunk[r]
      else
        NoGunk[r]
      end}

    # URL shorteners/redirectors
    %w(
bit.ly bos.gl
cbsn.ws
dlvr.it
econ.trib.al
feedproxy.google.com feeds.feedburner.com feeds.reuters.com
hubs.ly okt.to
reut.rs rss.cnn.com rssfeeds.usatoday.com
t.co ti.me tinyurl.com trib.al
w.bos.gl wired.trib.al
).map{|s| GET s, NoQuery}

    DenyDomains['com'].delete 'amazon' if ENV.has_key? 'AMAZON'

    GET 'gitter.im', -> r {
      r.env[:sort] = 'date'
      r.env[:view] = 'table'
      if r.parts[0] == 'api'
        token = ('//' + r.host + '/.token').R
        if !r.env.has_key?('x-access-token') && token.node.exist?
          r.env['x-access-token'] = token.readFile
        end
      end
      NoGunk[r]}

    %w(bostonglobe-prod.cdn.arcpublishing.com).map{|host| GET host, Resizer }

    DenyDomains['com'].delete 'facebook' if ENV.has_key? 'FACEBOOK'

    %w(l.facebook.com l.instagram.com).map{|host| GET host, GotoURL}

    GET 'detectportal.firefox.com', -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}
    GET 'gate.sc', GotoURL

    GotoAdURL =  -> r {
      if url = (r.query_values || {})['adurl']
        dest = url.R
        dest.query = '' unless url.match? /dest_url/
        [301, {'Location' => dest}, []]
      else
        r.deny
      end}

    GET 'googleads.g.doubleclick.net', GotoAdURL
    GET 'googleweblight.com', GotoURL
    GET 'google.com', -> r {[301, {'Location' => ['http://localhost:8000/www.google.com', r.path, '?', r.query].join}, []]}
    GET 'www.google.com', -> r {![nil, *%w(logos maps search url)].member?(r.parts[0]) ? r.deny : (r.path == '/url' ? GotoURL : NoGunk)[r]}
    GET 'www.googleadservices.com', GotoAdURL
    GET 'www.gstatic.com', -> r {r.path.match?(/204$/) ? [204,{},[]] : NoGunk[r]}

    GET 'old.reddit.com', -> r {
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          head['Location'] = r.join(head['Location']).R.href if head['Location']
          [status, head, body]
        else # find page pointer missing in HEAD (old+new UI) and HTML+RSS body (new UI) TODO find it presumably buried in JSON inside a script tag or some followon XHR
          links = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|link|links << CGI.unescapeHTML(link[0]).R} # find links
          [302, {'Location' => (links.empty? ? r : links.sort_by{|r|r.query_values['count'].to_i}[-1]).href.to_s.sub('old','www')}, []] # goto link with highest count
        end}}

    GET 'www.reddit.com', -> r {
      r.env[:links][:prev] = ['http://localhost:8000/old.reddit.com', r.path.sub('.rss',''), '?',r.query].join # page pointer
      if r.parts[-1] == 'new'
        r.env[:sort] = 'date'
        r.env[:view] = 'table'
      end
      r.path += '.rss' if !r.path.index('.rss') && %w(r u user).member?(r.parts[0]) # request RSS representation
      NoGunk[r]}

    GET 's4.reutersmedia.net', -> r {
      args = r.query_values || {}
      if args.has_key? 'w'
        args.delete 'w'
        [301, {'Location' => (qs args)}, []]
      else
        NoGunk[r]
      end}

    Twits = %w(
5_13Dist 792QFD 857FirePhotos
ActCal AestheticResear AlertBoston AlertsBoston AnnissaForBos ArchivesBoston ArtsinBoston AssignGuy AyannaPressley advocatenewsma ajafarzadehPR alertpageboston
BCYFcenters BHA_Boston billbostonis BOSCityCouncil BOSTON_WATER BPDPCGross BankerTradesman BansheeBoston BayStateBanner BillForry BlairMillerTV BosBizAllison BosBizJournal Boston25Photogs Boston25photog BostonBTD BostonBldgRes BostonFire BostonFireAlert BostonGlobe BostonHassle BostonLca BostonMagazine BostonNewsMan BostonPWD BostonParksDept BostonPlans BostonPoliceRA BostonRev BostonSchools BostonTVPhotog BostonWomen Boston_Fireman Boston_PFD BreakngNewsPhtg beetlenaut bfdradio blarneystonedot bosimpact boston25 bostonpolice bpsnews BrocktonBoxerz bytimlogan
CFamaWBZ CJPFirePhotos CampbellforD4 ChelseaScanner ChiefJoeFinn CityBosYouth CityLife_Clvu CityOfBoston CityofQuincy CodmanHealth CommonWealthMag CotterReporter cdinopoulos chipgoines chipsy231
Dan_Adams86 DorchesterBrew DorchesterNorth DotHistorical DotNews DotWrite dbedc doogs1227
ENG1SFD EdforBoston EirePub
Fairmount_Lab FieldsCornerMS FireSafeCorp FortPointer FranklinParkBos fiahspahk franksansev
GARYD117 GlobeMetro GlobeOpinion GreenovateBos gavin86077173 gavinschoch greaterashmont
HelloGreenway
JLDifazio JTrufant_Ledger JennDotSmith JohnAKeith janovember3 jenyp jrquin1234
Karynregal KerriCorrado Kim_Janey KristinaRex kathrynburcham kennycooks kwilesjrnews
LDBpeaceInst LOCAL_718 LaurieWBZ LiamWBZ LiveBoston617 LouisaMoller LydiaMEdwards lawrencepolice
MAFIREFIGHTER1 MAPCMetroBoston MBTA MBuffs MaFireEMS MadisonParkDC MarcHurBoston MartyForBoston MassArt MassDOT MassDev MassInno MassStatePolice MattOMalley MikeLaCrosseWBZ markpothier marty_walsh matredsoxfan2 mattgrobo metro_notify mfflaherty
NBC10Boston NECN NE_FireBuffs NiaNBCBoston NotoriousVOG news_bnn nickcollinsma nina_liang nuestradavid
ONS_Chinatown ofsevit
PatriotLedger PaulNuttingJr PaulaEbbenWBZ PlunkettPrime ProRockThrower pain24seven pictureboston
QuincyQuarry quincymapolice
RevereJournal radio615 reverescanner rgoulston
SBHealthCenter ScanBoston SquantumScoop Stizzy_LeftLane StreetsBoston StreetsblogMASS StringerBoston SunwealthPower scotteisenphoto sjforman138 skoczela stacos stevebikes susantran
TAGlobe TMGormanPhotos The_BMC ThomasCranePL thecrimehub therealreporter
UMassBoston universalhub
ViolenceNBoston
WBUR WBZTraffic WCVB WalkBoston WelcomeToDot WestWalksbury wbz wbznewsradio wgbhnews wutrain)

    GET 'twitter.com', -> r {
      r.env[:sort] = 'date'
      r.env[:view] = 'table'
      parts = r.parts
      qs = r.query_values || {}
      cookie = 'twitter/cookie'.R
      cookie.writeFile qs['cookie'] if qs.has_key? 'cookie' # update cookie
      if cookie.node.exist?                                 # set headers from cookie values
        attrs = {}
        r.env['HTTP_COOKIE'] = cookie.readFile
        r.env['HTTP_COOKIE'].split(';').map{|attr|
          k, v = attr.split('=').map &:strip
          attrs[k] = v}
        r.env['authorization'] ||= 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
        r.env['x-csrf-token'] ||= attrs['ct0'] if attrs['ct0']
        r.env['x-guest-token'] ||= attrs['gt'] if attrs['gt']
      end
      # feed
      if !r.path || r.path == '/'
        Twits.shuffle.each_slice(18){|sub|
          print '🐦'
          q = sub.map{|u|'from%3A' + u}.join('%2BOR%2B')
          apiURL = 'https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=' + q + '&vertical=default&count=40&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2CcameraMoment'
          apiURL.R(r.env).fetchHTTP thru: false}
        r.saveRDF.graphResponse
      # user
      elsif parts.size == 1 && !%w(favicon.ico manifest.json push_service_worker.js search sw.js).member?(parts[0])
        uid = nil
        # find uid
        uidQuery = "https://api.twitter.com/graphql/-xfUfZsnR_zqjFd-IfrN5A/UserByScreenName?variables=%7B%22screen_name%22%3A%22#{parts[0]}%22%2C%22withHighlightedLabel%22%3Atrue%7D"
        URI.open(uidQuery, r.headers){|response| # find uid
          body = HTTP.decompress response.meta, response.read
          json = ::JSON.parse body
          uid = json['data']['user']['rest_id']
          # find tweets
          ('https://api.twitter.com/2/timeline/profile/' + uid + '.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&include_tweet_replies=false&userId=' + uid + '&count=20&ext=mediaStats%2CcameraMoment').R(r.env).fetch}
      # conversation
      elsif parts.member?('status') || parts.member?('statuses')
        convo = parts.find{|p| p.match? /^\d{8}\d+$/ }
        "https://api.twitter.com/2/timeline/conversation/#{convo}.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&count=20&ext=mediaStats%2CcameraMoment".R(r.env).fetch
      # hashtag
      elsif parts[0] == 'hashtag'
        "https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=%23#{parts[1]}&count=20&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2ChighlightedLabel%2CcameraMoment".R(r.env).fetch
      else
        NoGunk[r]
      end}

    GET 's.yimg.com', -> r {
      ps = r.path.split /https?:\/+/
      ps.size > 1 ? [301, {'Location' => ('https://' + ps[-1]).R(r.env).href}, []] : r.deny}

    GET 'soundcloud.com', -> r {
      if (r.query_values || {}).has_key?('dl')
        storage = 'a/soundcloud' + r.path
        unless File.directory? storage
          FileUtils.mkdir_p storage
          pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{r.uri}\""
          Process.detach pid
        end
        [302, {'Location' => '/' + storage + '/'}, []]
      else
        r.env[:downloadable] = :audio
        NoGunk[r]
      end}

    GET 'youtube.com',   -> r {[301, {'Location' => ['http://localhost:8000/www.youtube.com', r.path, '?', r.query].join}, []]}
    GET 'm.youtube.com', -> r {[301, {'Location' => ['http://localhost:8000/www.youtube.com', r.path, '?', r.query].join}, []]}

    GET 'www.youtube.com', -> r {
      path = r.parts[0]
      qs = r.query_values || {}
      if %w{attribution_link redirect}.member? path
        [301, {'Location' => qs['q'] || qs['u']}, []]
      elsif %w(browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist results s user watch watch_videos yts).member?(path) || !path
        cookie = 'youtube/cookie'.R
        cookie.writeFile qs['cookie'] if qs.has_key? 'cookie'
        r.env['HTTP_COOKIE'] = cookie.readFile if cookie.node.exist?
        if path == 'embed'
          r.fetchHTTP transformable: false
        elsif path == 'watch' && qs.has_key?('dl')
          storage = 'a/youtube/' + (qs['list'] || qs['v'])
          unless File.directory? storage
            FileUtils.mkdir_p storage
            pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{r.uri}\""
            Process.detach pid
          end
          [302, {'Location' => '/' + storage + '/'}, []]
        else
          r.env[:downloadable] = :audio
          r.fetch
        end
      else
        r.deny
      end}
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

  def AX doc, &b
    doc.css('script').map{|script|
      if script.inner_text.match? /.*window.runParams = /
        Webize::JSON::Reader.new(script.inner_text.lines.grep(/^\s*data/)[0].sub(/^[^{]+/,'')[0...-2], base_uri: self).scanContent &b
      end}
  end

  def CityData doc
    doc.css("table[id^='post']").map{|post|
      subject = join '#' + post['id']
      yield subject, Type, Post.R
      post.css('a.bigusername').map{|user|
        yield subject, Creator, (join user['href'])
        yield subject, Creator, user.inner_text }
      post.css("div[id^='post_message']").map{|content|
        yield subject, Content, Webize::HTML.format(content.inner_html, self)}
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
      post.remove }
    ['#fixed_sidebar'].map{|s|doc.css(s).map &:remove}
  end

  def Drudge doc
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

      yield subject, Content, Webize::HTML.format((item.css('.comment-body')[0] || item).inner_html, self)

      if time = item.css('[datetime]')[0]
        yield subject, Date, time['datetime']
      end

      if author = item.css('.author, .opened-by > a')[0]
        yield subject, Creator, join(author['href'])
        yield subject, Creator, author.inner_text
      end

      yield subject, To, self
      item.remove
    }
  end

  def GitterHTML doc
    doc.css('script').map{|script|
      text = script.inner_text
      if text.match? /^window.gitterClientEnv/
        if token = text.match(/accessToken":"([^"]+)/)
          token = token[1]
          tFile = 'im/gitter/.token'.R
          unless tFile.node.exist? && tFile.readFile == token
            tFile.writeFile token
            puts ['🎫 ', host, token].join ' '
          end
        end
        if room = text.match(/"id":"([^"]+)/)
          env[:links][:prev] = 'http://gitter.im/api/v1/rooms/' + room[1] + '/chatMessages?lookups%5B%5D=user&includeThreads=false&limit=47'
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
      yield subject, Content, (Webize::HTML.format msg.css('.chat-item__text')[0].inner_html, self)
      if image = msg.css('.avatar__image')[0]
        yield subject, Image, image['src'].R
      end
      yield subject, Date, '%03d' % messageCount += 1
      msg.remove }
    doc.css('header').map &:remove
  end

  def GitterJSON tree, &b
    return if tree.class == Array
    return unless items = tree['items']
    items.map{|item|
      id = item['id']
      env[:links][:prev] ||= 'http://gitter.im/api/v1/rooms/' + parts[3] + '/chatMessages?lookups%5B%5D=user&includeThreads=false&beforeId=' + id + '&limit=47'
      date = item['sent']
      uid = item['fromUser']
      user = tree['lookups']['users'][uid]
      graph = [date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), 'gitter', user['username'], id].join('.').R # graph URI
      subject = 'http://gitter.im' + path + '?at=' + id # subject URI
      yield subject, Date, date, graph
      yield subject, Type, Post.R, graph
      yield subject, Creator, join(user['url']), graph
      yield subject, Creator, user['displayName'], graph
      yield subject, Image, user['avatarUrl'], graph
      yield subject, Content, (Webize::HTML.format item['html'], self), graph
    }
  end

  def GoogleHTML doc
    doc.css('svg').map &:remove
    doc.css('div.rc').map{|rc|
      if r = rc.css('div.r > a')[0]
        subject = r['href']
        yield subject, Type, Post.R
        if title = r.css('h3')[0]
          yield subject, Title, title.inner_text
        end
        if cite = r.css('cite')[0]
          yield subject, Link, cite.inner_text.R
        end
        if s = rc.css('div.s')[0]
          yield subject, Content, Webize::HTML.format(s.inner_html, self)
          rc.remove
        end
      end}
  end

  def HackerNews doc
    base = 'https://news.ycombinator.com/'
    # stories
    doc.css('a.storylink').map{|story|
      story_row = story.parent.parent
      comments_row = story_row.next_sibling
      subject = join comments_row.css('a')[-1]['href']
      yield subject, Type, Post.R
      yield subject, Title, story.inner_text
      yield subject, Link, story['href']
      yield subject, Date, (Chronic.parse(comments_row.css('.age > a')[0].inner_text.sub(/^on /,'')) || Time.now).iso8601
      story_row.remove
      comments_row.remove
    }
    # comments
    doc.css('div.comment').map{|comment|
      post = comment.parent
      date = post.css('.age > a')[0]
      subject = base + date['href']
      comment.css('.reply').remove
      yield subject, Type, Post.R
      yield subject, Content, (Webize::HTML.format comment.inner_html, self)
      if user = post.css('.hnuser')[0]
        yield subject, Creator, (base + user['href']).R
        yield subject, Creator, user.inner_text
      end
      yield subject, To, self
      if parent = post.css('.par > a')[0]
        yield subject, To, (base + parent['href']).R
      end
      if story = post.css('.storyon > a')[0]
        yield subject, To, (base + story['href']).R
        yield subject, Title, story.inner_text
      end
      if time = (Chronic.parse date.inner_text.sub(/^on /,''))
        yield subject, Date, time.iso8601
      end
      post.remove }
  end

  def InstagramHTML doc, &b
    objvar = /^window._sharedData = /
    doc.css('script').map{|script|
      if script.inner_text.match? objvar
        InstagramJSON ::JSON.parse(script.inner_text.sub(objvar, '')[0..-2]), &b
      end}
  end

  def InstagramJSON tree, &b
    Webize::HTML.webizeHash(tree){|h|
      if tl = h['edge_owner_to_timeline_media']
        end_cursor = tl['page_info']['end_cursor'] rescue nil
        uid = tl["edges"][0]["node"]["owner"]["id"] rescue nil
        env[:links][:prev] ||= 'https://www.instagram.com/graphql/query/' + HTTP.qs({query_hash: :e769aa130647d2354c40ea6a439bfc08, variables: {id: uid, first: 12, after: end_cursor}.to_json}) if uid && end_cursor
      end
      yield ('https://www.instagram.com/' + h['username']).R, Type, Person.R if h['username']
      if h['shortcode']
        s = 'https://www.instagram.com/p/' + h['shortcode'] + '/'
        yield s, Type, Post.R
        yield s, Image, h['display_url'].R if h['display_url']
        if owner = h['owner']
          yield s, Creator, ('https://www.instagram.com/' + owner['username']).R if owner['username']
          yield s, To, 'https://www.instagram.com/'.R
        end
        if time = h['taken_at_timestamp']
          yield s, Date, Time.at(time).iso8601
        end
        if text = h['edge_media_to_caption']['edges'][0]['node']['text']
          yield s, Content, CGI.escapeHTML(text).split(' ').map{|t|
                if match = (t.match /^@([a-zA-Z0-9._]+)(.*)/)
                  "<a id='u#{Digest::SHA2.hexdigest rand.to_s}' class='uri' href='https://www.instagram.com/#{match[1]}'>#{match[1]}</a>#{match[2]}"
                else
                  t
                end}.join(' ')
        end rescue nil
      end
    }
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
      subject = (join post_link['href']).R
      graph = subject.join [subject.basename, subject.fragment].join '.'
      yield subject, Type, Post.R, graph
      yield subject, To, (join subject.path), graph
      yield subject, Creator, (join author['href']), graph
      yield subject, Creator, author.inner_text, graph
      yield subject, Image, (join avatar.css('img')[0]['src']), graph
      yield subject, Date, Time.parse(comment.css('.byline > span[title]')[0]['title']).iso8601, graph
      yield subject, Content, (Webize::HTML.format comment.css('.comment_text')[0].inner_html, self), graph

      comment.remove }
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
      graph = [date.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), station, show_name.split(' ')].join('.').R # graph URI
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
    if objects = (tree.class != Array) && tree['globalObjects']
      users = objects['users'] || {}
      (objects['tweets'] || {}).map{|id, tweet|
        id = tweet['id_str']
        uid = tweet['user_id_str']
        userinfo = users[uid] || {}
        username = userinfo['screen_name'] || 'anonymous'
        user = 'https://twitter.com/' + username
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
  end

  def UHub doc
    doc.css('.pager-next > a[href]').map{|n| env[:links][:next] ||= n['href'] }
    doc.css('.pager-previous > a[href]').map{|p| env[:links][:prev] ||= p['href'] }
  end

  def YouTube doc, &b; dataVar = /window..ytInitial/
    doc.css('script').map{|script|
      if script.inner_text.match? dataVar
        script.inner_text.lines.grep(dataVar).map{|line|
          Webize::JSON::Reader.new(line.sub(/^[^{]+/,'')[0...-2], base_uri: self).scanContent &b}
      end}
  end

end
