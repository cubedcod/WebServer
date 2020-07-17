# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        '8kun.top' => :Chan,
        'apnews.com' => :AP,
        'bunkerchan.xyz' => :Chan,
        'drudgereport.com' => :Drudge,
        'archive.4plebs.org' => :FourPlebs,
        'boards.4chan.org' => :Chan,
        'boards.4channel.org' => :Chan,
        'github.com' => :GitHub,
        'gitter.im' => :GitterHTML,
        'news.ycombinator.com' => :HackerNews,
        'universalhub.com' => :UHub,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :InstagramHTML,
        'www.qrz.com' => :QRZ,
        'www.universalhub.com' => :UHub,
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
    StaticFormats = %w(bin css geojson gif ico jpeg jpg js m3u8 m4a mp3 mp4 opus pem pdf png svg ts webm webp .ico .gif .jpg .png .mp4 .js) # formats requiring URI change for cache-invalidation
    AllowedHeaders = 'authorization, client-id, content-type, device-fp, device-id, x-access-token, x-braze-api-key, x-braze-datarequest, x-braze-triggersrequest, x-csrf-token, x-device-id, x-goog-authuser, x-guest-token, x-hostname, x-lib-version, x-locale, x-twitter-active-user, x-twitter-client-language, x-twitter-utcoffset, x-requested-with' # TODO populate from preflight

    # local resources
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd
    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteIcon = SiteDir.join('favicon.ico').read
    SiteCSS = SiteDir.join('site.css').read
    CodeCSS = SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read

  end
  module HTTP

    # handler lambdas

    GoAU =  -> r {
      if url = (r.query_values || {})['adurl']
        dest = url.R
        dest.query = '' unless url.match? /dest_url/
        [301, {'Location' => dest}, []]
      else
        r.deny
      end}

    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['u']||r.query_values['q'])}, []]}
    NoGunk  = -> r {r.send r.uri.match?(Gunk) ? :deny : :fetch}
    NoProxy = -> r {r.parts[0] == 'proxy' ? r.deny(200, :image) : NoGunk[r]}
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
        parts.size > 1 ? [302,
                          {'Location' => 'https://' + parts[-1]
                          }, []] : NoJS[r]
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

    # video APIs
    %w(entitlement.auth.adobe.com sp.auth.adobe.com tkx.apis.anvato.net
edge.api.brightcove.com players.brightcove.net secure.brightcove.com
api.lbry.com api.lbry.tv lbry.tv
graphql.api.dailymotion.com).map{|h| Allow h}

    GET 'www.amazon.com'

    GET 'gitter.im', -> r {
      if r.parts[0] == 'api'
        token = ('//' + r.host + '/.token').R
        if !r.env.has_key?('x-access-token') && token.node.exist?
          r.env['x-access-token'] = token.readFile
        end
      end
      NoGunk[r]}

    %w(bostonglobe-prod.cdn.arcpublishing.com).map{|host| GET host, Resizer }

    if ENV.has_key? 'FACEBOOK'
      GET 'www.facebook.com'
    end
    %w(l.facebook.com l.instagram.com).map{|host| GET host, GotoURL}

    GET 'detectportal.firefox.com', -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}
    GET 'gate.sc', GotoURL

    if ENV.has_key? 'GOOGLE'
      %w(aa books groups).map{|h|                                               Allow h + '.google.com' }
      %w(update).map{|h|                                                        Allow h + '.googleapis.com' }
      %w(cse developers dl docs drive images kh khms0 khms1 khms2 khms3 lh3 maps news photos sites).map{|h|
                                                                                  GET h + '.google.com' }
      %w(encrypted-tbn0 encrypted-tbn1 encrypted-tbn2 encrypted-tbn3 encrypted-vtbn3 maps ssl www).map{|h|
                                                                                  GET h + '.gstatic.com' }
      %w(geo0 geo1 geo2 geo3 lh3 lh4 lh5 lh6).map{|h|                             GET h + '.ggpht.com' }
      %w(maps storage).map{|h|                                                    GET h + '.googleapis.com' }
      (3..6).map{|i|                                                              GET "lh#{i}.googleusercontent.com", NoProxy}
      GET 'ad.doubleclick.net', -> r {[301, {'Location' => 'https://en.wikipedia.org/wiki/Special:Random'}, []]}
      GET 'googleads.g.doubleclick.net', GoAU
      GET 'googleweblight.com', GotoURL
      GET 'google.com', -> r {[301, {'Location' => ['http://localhost:8000/www.google.com', r.path, '?', r.query].join}, []]}
      GET 'www.google.com', -> r {![nil, *%w(dl maps search url)].member?(r.parts[0]) ? r.deny : (r.path == '/url' ? GotoURL : NoGunk)[r]}
      GET 'www.googleadservices.com', GoAU
      GET 'yt3.ggpht.com', NoProxy
    end

    GET 'developer.mozilla.org'

    GET 'old.reddit.com', -> r {
      cr = r.env[:cacherefs]
      r.env[:cacherefs] = false # don't rewrite references in fetch response
      r.fetch.yield_self{|status,head,body|
        if status.to_s.match? /^30/
          [status, head, body]
        else # find page pointers missing in HEAD (old + new UI) and HTML/RSS bodies (new UI)
          links = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|link|links << CGI.unescapeHTML(link[0]).R} # find links
          link = links.empty? ? r : links.sort_by{|r|r.query_values['count'].to_i}[-1]         # sort links
          nextPage = ['https://www.reddit.com', link.path, '?', link.query].join.R r.env       # page reference
          r.env[:cacherefs] = cr # restore rewrite settings
          [302, {'Location' => nextPage.href}, []]
        end}}

    GET 'www.reddit.com', -> r {
      cookie = 'reddit/.cookie'.R
      if cookie.node.exist?
        r.env['HTTP_COOKIE'] = cookie.readFile
      elsif r.env['HTTP_COOKIE']
        cookie.writeFile r.env['HTTP_COOKIE']
      end
      submitUI = r.parts[-1] == 'submit'
      r.env[:links][:prev] = ['https://old.reddit.com',r.path,'?',r.query].join # pagination pointer
      r.path += '.rss' if r.ext.empty? && %w(r u user).member?(r.parts[0]) && !submitUI && !(r.query_values||{}).has_key?('UI') # request RSS format on user and thread pages
      r.fetchHTTP transformable: !submitUI}

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
BCYFcenters BHA_Boston BILL34793923 BOSCityCouncil BOSTON_WATER BPDPCGross BankerTradesman BansheeBoston BayStateBanner BillForry BlairMillerTV BosBizAllison BosBizJournal Boston25Photogs Boston25photog BostonBTD BostonBldgRes BostonFire BostonFireAlert BostonGlobe BostonHassle BostonLca BostonMagazine BostonNewsMan BostonPWD BostonParksDept BostonPlans BostonPoliceRA BostonRev BostonSchools BostonTVPhotog BostonWomen Boston_Fireman Boston_PFD BreakngNewsPhtg beetlenaut bfdradio blarneystonedot bosimpact boston25 bostonpolice bpsnews bytimlogan
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

    #Allow 'api.twitter.com'
    GET 'twitter.com', -> r {
      parts = r.parts
      cookie = 'twitter/.cookie'.R

      if r.env[:cacherefs] && cookie.node.exist?
        r.env['HTTP_COOKIE'] = cookie.readFile
      elsif r.env['HTTP_COOKIE'] && r.env['HTTP_COOKIE'].match?(/ct0/)
        cookie.writeFile r.env['HTTP_COOKIE']
      end

      if reqCookie = r.env['HTTP_COOKIE']
        attrs = {}
        reqCookie.split(';').map{|attr|
          k, v = attr.split('=').map &:strip
          attrs[k] = v}
        r.env['authorization'] ||= 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
        r.env['x-csrf-token'] ||= attrs['ct0'] if attrs['ct0']
        r.env['x-guest-token'] ||= attrs['gt'] if attrs['gt']
      end

      remoteUI = -> {
        cookie.node.delete if cookie.node.exist?
        %w(authorization x-csrf-token x-guest-token HTTP_COOKIE).map{|k| r.env.delete k}
        r.fetchHTTP transformable: false}

      # feed
      if !r.path || r.path == '/'
        Twits.shuffle.each_slice(18){|sub|
          print '🐦'
          q = sub.map{|u|'from%3A' + u}.join('%2BOR%2B')
          apiURL = 'https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=' + q + '&vertical=default&count=40&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2CcameraMoment'
          apiURL.R(r.env).fetchHTTP cache: false, response: false}
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
          ('https://api.twitter.com/2/timeline/profile/' + uid + '.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&include_tweet_replies=false&userId=' + uid + '&count=20&ext=mediaStats%2CcameraMoment').R(r.env).fetchHTTP transform: true} rescue remoteUI[]
      # conversation
      elsif parts.member?('status') || parts.member?('statuses')
        convo = parts.find{|p| p.match? /^\d{8}\d+$/ }
        "https://api.twitter.com/2/timeline/conversation/#{convo}.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&count=20&ext=mediaStats%2CcameraMoment".R(r.env).fetchHTTP transform: true
      # hashtag
      elsif parts[0] == 'hashtag'
        "https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=%23#{parts[1]}&count=20&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2ChighlightedLabel%2CcameraMoment".R(r.env).fetchHTTP transform: true
      else
        NoGunk[r]
      end.yield_self{|s,h,b|
        [403, 404, 429].member?(s) ? remoteUI[] : [s,h,b]}}

    GET 's.yimg.com', -> r {
      ps = r.path.split /https?:\/+/
      ps.size > 1 ? [301, {'Location' => ('https://' + ps[-1]).R(r.env).href}, []] : r.deny}

    GET 'www.youtube.com', -> r {
      path = r.parts[0]
      if !path
        [301, {'Location' => '//www.youtube.com/feed/subscriptions'.R(r.env).href}, []]
      elsif %w{attribution_link redirect}.member? path
        [301, {'Location' => r.query_values['q'] || r.query_values['u']}, []]
      elsif %w(browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist results s user watch watch_videos yts).member? path
        cookie = 'youtube/.cookie'.R
        if cookie.node.exist?
          r.env['HTTP_COOKIE'] = cookie.readFile
        elsif r.env['HTTP_COOKIE'] && r.env['HTTP_COOKIE'].match?(/LOGIN/)
          cookie.writeFile r.env['HTTP_COOKIE']
        end
        if path == 'embed'
          r.fetchHTTP transformable: false
        elsif path == 'watch' && (r.query_values || {}).has_key?('dl')
          storage = [r.fsPath, r.query_hash].join.R
          unless File.directory? storage
            pid = spawn "youtube-dl -o '#{storage}/%(title)s.%(ext)s' -x \"#{r.uri}\""
            Process.detach pid
          end
          if file = storage.node.exist? && storage.node.children[0]
            file.R(r.env).fileResponse
          else
            [404, {'Content-Type' => 'text/html'}, ['downloading..']]
          end
        else
          r.env[:downloadable] = :audio
          r.fetch
        end
      else
        r.deny
      end}
  end

  def AP doc, &f
    doc.css('script').map{|script|
      script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data|
        data = data[0]
        data = data[0..-2] if data[-1] == ';'
        Webize::JSON::Reader.new(data, base_uri: self).scanContent &f}}
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

  def Chan doc
    doc.css('.post, .postCell').map{|post|
      number = post.css('a.post_no, .postNum a')[0]
      subject = join(number ? number['href'] : ('#' + (post['id'] || (Digest::SHA2.hexdigest post.to_s))))
      graph = ['https://', subject.host, subject.path, '/', subject.fragment].join.R

      yield subject, Type, Post.R, graph

      post.css('.name').map{|name|
        yield subject, Creator, name.inner_text, graph }

      post.css('time, .dateTime').map{|date|
        yield subject, Date,
              Time.at((date['data-utc'] ||
                       date['unixtime']).to_i).iso8601, graph }

      post.css('.labelCreated').map{|created|
        yield subject, Date, Chronic.parse(created.inner_text).iso8601, graph}

      post.css('.subject, .title').map{|subj|
        yield subject, Title, subj.inner_text, graph }

      post.css('.body, .divMessage, .postMessage').map{|msg|
        yield subject, Content, msg, graph }

      post.css('.fileThumb, .imgLink').map{|a|
        yield subject, Image, a['href'].R, graph if a['href'] }

      post.css('.post-image').map{|img|
        yield subject, Image, img.parent['href'].R, graph}

      post.remove }
  end

  def Drudge doc
  end

  def FourPlebs doc
    doc.css('.post').map{|post|
      subject = join '#' + post['id']
                                          yield subject, Type,    Post.R
      post.css('.post_author').map{|name| yield subject, Creator, name.inner_text }
      post.css(        'time').map{|time| yield subject, Date,    time['datetime'] }
      post.css( '.post_title').map{|subj| yield subject, Title,   subj.inner_text }
      post.css(       '.text').map{|msg|  yield subject, Content, msg }
      post.css('.post_image').map{|img|   yield subject, Image,   img['src'].R if img['src']}
      post.remove}
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
      if issue = item.css("[data-hovercard-type='issue']")[0]
        yield subject, Title, issue.inner_text
        yield subject, Link, join(issue['href'])
        issue.remove
      end
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
          env[:links][:prev] = 'http://gitter.im/api/v1/rooms/' + room[1] + '/chatMessages?lookups%5B%5D=user&includeThreads=false&limit=47&view=table&sort=date&rdf'
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
      env[:links][:prev] ||= 'http://gitter.im/api/v1/rooms/' + parts[3] + '/chatMessages?lookups%5B%5D=user&includeThreads=false&beforeId=' + id + '&limit=47&view=table&sort=date&rdf'
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

  IGgraph = /^window._sharedData = /

  def InstagramHTML doc, &b
    doc.css('script').map{|script|
      if script.inner_text.match? IGgraph
        InstagramJSON ::JSON.parse(script.inner_text.sub(IGgraph,'')[0..-2]), &b
      end}
  end

  def InstagramJSON tree, &b
    Webize::HTML.webizeHash(tree){|h|
      if tl = h['edge_owner_to_timeline_media']
        end_cursor = tl['page_info']['end_cursor'] rescue nil
        uid = tl["edges"][0]["node"]["owner"]["id"] rescue nil
        env[:links][:prev] ||= 'https://www.instagram.com/graphql/query/' + HTTP.qs({query_hash: :e769aa130647d2354c40ea6a439bfc08, rdf: :rdf, variables: {id: uid, first: 12, after: end_cursor}.to_json}) if uid && end_cursor
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

  def QRZ doc, &b
    doc.css('script').map{|script|
      script.inner_text.scan(%r(biodata'\).html\(\s*Base64.decode\("([^"]+))xi){|data|
        yield self, Content, Base64.decode64(data[0]).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')}}
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

end
