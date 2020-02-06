# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        'apnews.com' => :AP,
        'github.com' => :GitHub,
        'gitter.im' => :Gitter,
        'lwn.net' => :LWN,
        'news.ycombinator.com' => :HackerNews,
        'twitter.com' => :TwitterHTML,
        'universalhub.com' => :UHub,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :InstagramHTML,
        'www.patriotledger.com' => :GateHouse,
        'www.providencejournal.com' => :GateHouse,
        'www.universalhub.com' => :UHub,
        'www.youtube.com' => :YouTubeHTML,
      }
    end
  end
  module JSON
    Triplr = {
      'twitter.com' => :TwitterHTMLinJSON,
      'api.twitter.com' => :TwitterJSON,
      'gateway.reddit.com' => :RedditJSON,
      'outline.com' => :Outline,
      'outlineapi.com' => :Outline,
      'www.instagram.com' => :InstagramJSON,
      'www.youtube.com' => :YouTubeJSON,
    }
  end
end
class WebResource
  module URIs
    CacheExt = %w(css geojson gif html ico jpeg jpg js json m3u8 m4a md mp3 mp4 opus pdf png svg ts webm webp xml) # cached filetypes
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd
    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteGIF = SiteDir.join('site.gif').read
    SiteCSS = SiteDir.join('site.css').read
    CodeCSS = SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
  end
  module HTTP

    CDNhost = /\.(akamai(hd)?|amazonaws|.*cdn|cloud(f(lare|ront)|inary)|fastly|github|googleapis|netdna.*)\.(com|io|net)$/
    CookieHost = /\.(akamai(hd)?|bandcamp|ttvnw)\.(com|net)$/
    DynamicImgHost = /(noaa|weather)\.gov$/
    POSThost = /^video.*.ttvnw.net$/
    GunkHosts = {}
    SiteDir.join('gunk_hosts').each_line{|l|
      cursor = GunkHosts
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|cursor = cursor[name] ||= {}}}

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : NoGunk[r]
      else
        NoGunk[r]
      end}

    # ABC
    GET 'abcnews.go.com'
    GET 's.abcnews.com', NoJS

    # ACM
    Cookies 'dl.acm.org'

    # Adobe
    Allow 'entitlement.auth.adobe.com'
    Allow 'sp.auth.adobe.com'

    # Amazon
    AmazonHost = -> r {(%w(www.amazon.com www.imdb.com).member?(r.env[:refhost]) || r.env[:query]['allow'] == ServerKey) ? NoGunk[r] : r.deny}
    %w(amazon.com www.amazon.com).map{|host| GET host}
    GET 'images-na.ssl-images-amazon.com', AmazonHost
    GET 'm.media-amazon.com', AmazonHost

    # Apple
    %w(amp-api.music api.music audio-ssl.itunes embed.music itunes js-cdn.music music www xp).map{|h|Allow h + '.apple.com'}
    %w(store.storeimages).map{|h| GET h + '.cdn-apple.com'}

    # Appspot
    %w(xmountwashington).map{|h| Allow h + '.appspot.com'}

    # Anvato
    Allow 'tkx.apis.anvato.net'

    # Balamii
    Allow 'balamii-parse.herokuapp.com'
    Allow 'player.balamii.com'

    # Boston Globe
    GET 'bostonglobe-prod.cdn.arcpublishing.com', Resizer
    %w(bos.gl w.bos.gl).map{|short| GET short, NoQuery }
    Insecure 'bos.gl'

    # BrassRing
    Allow 'sjobs.brassring.com'

    # Brightcove
    %w(
edge.api.brightcove.com
players.brightcove.net
secure.brightcove.com
).map{|h|
      Allow h}

    # Brightspot
    %w(ca-times ewscripps wgbh).map{|h|
      GET h + '.brightspotcdn.com', GoIfURL}

    # BusinessWire
    GET 'cts.businesswire.com', GoIfURL

    # BuzzFeed
    GET 'img.buzzfeed.com'

    # CBS
    GET 'www.cbsnews.com'

    # CircleCI
    GET 'circleci.com', -> r {r.parts[0] == 'blog' ? r.fetch : r.deny}

    # Cloudflare
    GET 'cdnjs.cloudflare.com'

    # Complex
    %w(images www).map{|h| GET h + '.complex.com' }

    # Costco
    Allow 'www.costco.com'

    # CNet
    GET 'www.cnet.com'

    # CNN
    GET 'dynaimage.cdn.cnn.com', GotoBasename
    GET 'rss.cnn.com', NoQuery

    # DartSearch
    GET 'clickserve.dartsearch.net', -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # DI.fm
    Allow 'www.di.fm'

    # Disqus
    GET 'c.disquscdn.com'
    GET 'disq.us', GoIfURL

    # DuckDuckGo
    GET 'duckduckgo.com', -> r {
      sel = r.parts[0]
      if %w{ac}.member? sel
        r.deny
      elsif sel == 'l' && r.env[:query].has_key?('uddg')
        [301, {'Location' => r.env[:query]['uddg']}, []]
      else
        NoGunk[r]
      end}

    GET 'proxy.duckduckgo.com', -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.fetch}

    # eBay
    Allow 'www.ebay.com'
    %w(ebay.com
   www.ebay.com
    ir.ebaystatic.com
thumbs.ebaystatic.com).map{|host| GET host }

    GET 'i.ebayimg.com', -> r {r.basename.match?(/s-l(64|96|200|225).jpg/) ? [301, {'Location' => File.dirname(r.path) + '/s-l1600.jpg'}, []] : r.fetch}
    GET 'rover.ebay.com', -> r {r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # Economist
    GET 'www.economist.com'

    # ESPN
    %w(api-app broadband media.video-cdn secure site.api site.web.api watch.auth.api watch.graph.api www).map{|h|
      Allow h + '.espn.com' }

    %w(a a1 a2 a3 a4).map{|a| GET a + '.espncdn.com' }

    # Facebook
    if ENV.has_key?('FACEBOOK')
      %w(facebook.com business.facebook.com edge-chat.facebook.com m.facebook.com static.xx.fbcdn.net www.facebook.com).map{|host| Allow host }
      GET 'external.fbed1-2.fna.fbcdn.net', -> r {
        if r.path == '/safe_image.php'
          GotoURL[r]
        else
          NoGunk[r]
        end}
    end

    %w(l.facebook.com lm.facebook.com).map{|host| GET host, GotoU}

    # Feedburner
    GET 'feeds.feedburner.com', NoQuery

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => Rack::Utils.unescape(r.parts[-1])}, []]}

    # Gfycat
    GET 'gfycat.com'
    GET 'thumbs.gfycat.com'

    # GitHub
    GET 'github.com'
    %w(api gist).map{|h| GET h + '.github.com'}
    %w(avatars0 avatars1 avatars2 avatars3 raw).map{|h| GET h + '.githubusercontent.com', NoJS }

    # Gitter
    Allow 'gitter.im'
    Allow 'ws.gitter.im'

    # Google - set DEGOOGLE env-var to opt out
    unless ENV.has_key? 'DEGOOGLE'

      # POST capability
      Allow 'groups.google.com'
      if ENV.has_key? 'GOOGLE'
        Allow 'android.clients.google.com'
        (0..24).map{|i| h="#{i}.client-channel.google.com"; Allow h}
        (0..24).map{|i| Allow "clients#{i}.google.com"}
      end

      # restrict static-hosts to google referer
      GData = -> r {(r.env[:refhost]||'').match?(/\.(blog(ger|spot)|google(apis)?|gstatic)\.com$/) ? NoGunk[r] : r.deny}
      %w(maps ssl www).map{|h| GET h + '.googleapis.com', GData }
      %w(maps ssl www).map{|h| GET h + '.gstatic.com', GData }
      (0..3).map{|i| GET "encrypted-tbn#{i}.gstatic.com", GData }
      (0..3).map{|i| GET "khms#{i}.google.com", GData }

      # JS libraries, allow anyone
      GET 'ajax.googleapis.com'

      # misc hosts
      GET 'feedproxy.google.com', NoQuery

      # main Google site, allow personalization
      GET 'google.com', -> r {[301, {'Location' => 'https://www.google.com' + r.env['REQUEST_URI'] }, []]}
      Cookies 'www.google.com'
      GET 'www.google.com', -> r {
        case r.path
        when /^.(images|maps|xjs)/
          r.upstreamUI.env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/888.38 (KHTML, like Gecko) Chrome/80.0.3888.80 Safari/888.38'
          r.fetch
        when /^.search/ # full URLs are getting sent to /search on Android/Chrome. redirect to URL
          q = r.env[:query]['q']
          q && q.match?(/^(https?:|l(ocalhost)?(:8000)?)\//) && [301,{'Location'=>q.sub(/^l/,'http://l')},[]] || r.fetch
        when '/url'
          GotoURL[r]
        else
          GData[r]
        end}
    end

    # Guardian
    GET 'i.guim.co.uk'
    GET 'assets.guim.co.uk'
    GET 'www.theguardian.com'

    # HFU
    Allow 'chat.hfunderground.com'

    # Hubspot
    GET 'hubs.ly', NoQuery

    # iHeart
    Allow 'us.api.iheart.com'
    Allow 'www.iheart.com'
    GET 'i.iheart.com'

    # Imgur
    Allow 'api.imgur.com'
    %w(i.imgur.com i.stack.imgur.com).map{|host| GET host }

    %w(imgur.com
     m.imgur.com
     s.imgur.com
).map{|host| GET host}

    # Inrupt
    Allow 'dev.inrupt.net'

    # Invisible Books
    Insecure 'www.invisiblebooks.com'

    # Instagram
    Cookies 'www.instagram.com'
    GET 'l.instagram.com', GotoU
    GET 'www.instagram.com', RootIndex

    Populate 'www.instagram.com', -> r {
      base = 'instagram/'
      FileUtils.mkdir base
      names = {}
      `grep -E 'instagram.com/[[:alnum:]]+/? ' ../web.log`.each_line{|line|
        line.chomp.split(' ').map{|token|
          if token.match? /^https?:/
            name = token.split('/')[-1]
            unless names[name]
              names[name] = true
              FileUtils.mkdir base + name
            end
          end}}}

    IG  =  -> r {             [301, {'Location' => 'https://www.instagram.com'  + r.path},     []]         }
    IG0 =  -> r {r.parts[0] ? [301, {'Location' => 'https://www.instagram.com/' + r.parts[0]}, []] : r.deny}
    IG1 =  -> r {r.parts[1] ? [301, {'Location' => 'https://www.instagram.com/' + r.parts[1]}, []] : r.deny}

    %w(instagram.com).map{|host| GET host, IG}

    %w(
deskgram.cc deskgram.net
graphixto.com
instapuma.com
www.picimon.com picpanzee.com www.pictosee.com
saveig.org
www.toopics.com
).map{|host| GET host, IG0}

    %w(
gramho.com
insee.me instadigg.com www.instagimg.com
jolygram.com
pikdo.net piknu.com publicinsta.com www.pictame.com
rankersta.com
zoopps.com
).map{|host| GET host, IG1}

    # JWPlayer
    GET 'ssl.p.jwpcdn.com'

    # Linkedin
    Cookies 'www.linkedin.com'
    GET 'static-exp1.licdn.com'
    GET 'media.licdn.com'
    GET 'www.linkedin.com'

    # Mail.ru
    GET 'cloud.mail.ru'
    GET 'img.imgsmail.ru'
    GET 's.mail.ru'
    GET 'thumb.cloud.mail.ru'

    # MassLive
    GET 'i.masslive.com', Resizer

    # Mastodon
    %w(
assets.octodon.social
     drive.nya.social
files.mastodon.social
      mastodon.art
      mastodon.social
           pdx.social
           nya.social
       octodon.social
).map{|host|
      GET host, Fetch}

    # Medium
    Allow 'medium.com'

    # Meetup
    Allow 'www.meetup.com'
    GET 'www.meetup.com', Fetch

    # Meredith
    GET 'imagesvc.meredithcorp.io', GoIfURL

    # Microsoft
    GET 'www.bing.com'
    GET 'www.msn.com'

    # Mixcloud
    %w(m www).map{|h| GET h + '.mixcloud.com' }

    # Mozilla
    %w(            addons.mozilla.org
           addons-amo.cdn.mozilla.net
               addons.cdn.mozilla.net
                     aus5.mozilla.org
firefox.settings.services.mozilla.com
            getpocket.cdn.mozilla.net
                    hacks.mozilla.org
       incoming.telemetry.mozilla.org
        location.services.mozilla.com
          services.addons.mozilla.org
          shavar.services.mozilla.com
  tracking-protection.cdn.mozilla.net
).map{|h| Allow h } if ENV.has_key? 'MOZILLA'

    GET 'detectportal.firefox.com', -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Nextdoor
    Cookies 'nextdoor.com'

    # NOAA
    Allow 'forecast.weather.gov'

    # NYTimes
    %w(cooking www).map{|host|
      GET host+'.nytimes.com'}

    # Outline
    GET 'outline.com', -> r {
      if r.parts[0] == 'favicon.ico'
        r.deny
      else
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['SERVER_NAME'] = 'outlineapi.com'
        options = {cookies: true, intermediate: true}
        (if r.parts.size == 1
          options[:query] = {id: r.parts[0]}
          '/v4/get_article'.R(r.env).fetch options
        elsif r.env['REQUEST_PATH'][1..5] == 'https'
          options[:query] = {source_url: r.env['REQUEST_PATH'][1..-1]}
          '/article'.R(r.env).fetch options
         end).saveRDF.graphResponse
      end}

    # Patch
    GET 'patch.com', NoQuery

    # Reddit
    GotoReddit = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path + r.qs}, []]}
    %w(reddit-uploaded-media.s3-accelerate.amazonaws.com v.redd.it).map{|h| Allow h }
    %w(gateway gql oauth old s www).map{|h|                                 Allow h + '.reddit.com' }
    %w(np.reddit.com reddit.com).map{|host| GET host, GotoReddit }

    GET 'www.reddit.com', -> r { parts = r.parts
      r.chrono_sort if r.path == '/' || parts[-1] == 'new' || parts.size == 5                # chrono-sort preference
      r = ('//www.reddit.com/r/Bostonmusic+Dorchester+QuincyMa+Rad_Decentralization+SOLID+StallmanWasRight+boston+dancehall+darknetplan+fossdroid+massachusetts+roxbury+selfhosted+shortwave/new/').R r.env if r.path == '/' # subscriptions
      r.upstreamUI if parts[-1] == 'submit'                                                  # upstream UI preference
      options = {suffix: '.rss'} if r.ext.empty? && !r.upstreamUI? && !parts.member?('wiki') # MIME preference
      r.env[:links][:prev] = 'https://old.reddit.com' + r.path + r.qs # page pointers
      r.env[:links][:up] = File.dirname r.path unless r.path == '/'
      r.fetch options}

    # this host provides a next-page pointer, missing in HTTP Headers (either UI) and HTML (new UI)
    GET 'old.reddit.com', -> r {
      r.upstreamUI.env['HTTP_USER_AGENT'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/888.38 (KHTML, like Gecko) Chrome/80.0.3888.80 Safari/888.38'
      r.fetch.yield_self{|status,head,body|
        if !%w(r u user).member?(r.parts[0]) || status.to_s.match?(/^30/) # return redirects and wiki pages
          [status, head, body]
        else # find page pointer and redirect
          refs = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|l| refs << l[0] }
          if refs.empty?
            GotoReddit[r]
          else
            page = refs[-1].R
            [302, {'Location' => 'https://www.reddit.com' + page.path + page.qs}, []]
          end
        end
      }}

    # ResearchGate
    Cookies 'www.researchgate.net'

    # Reuters
    GET 'feeds.reuters.com', NoQuery
    (0..5).map{|i|
      GET "s#{i}.reutersmedia.net", -> r {
        if r.env[:query].has_key? 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + HTTP.qs(r.env[:query].reject{|k,_|k=='w'})}, []]
        else
          r.fetch
        end}}

    # Shopify
    GET 'cdn.shopify.com'

    # SkimResources
    GET 'go.skimresources.com', GotoURL
    GET 'c212.net', GotoU

    # Soundcloud
    GET 'gate.sc', GotoURL
    %w(api-auth.soundcloud.com
       api-mobi.soundcloud.com
     api-mobile.soundcloud.com
         api-v2.soundcloud.com
     api-widget.soundcloud.com
            api.soundcloud.com
                soundcloud.com
         secure.soundcloud.com
              w.soundcloud.com
).map{|host| Allow host
               GET host}
    GET 'soundcloud.com', RootIndex

    # Spotify
    %w(api apresolve embed guc-dealer guc-spclient open spclient.wg).map{|h|
      Allow h + '.spotify.com'}

    # StarTribune
    Allow 'comments.startribune.com'

    # Tableau
    Allow 'public.tableau.com'

    # Technology Review
    GET 'cdn.technologyreview.com', NoQuery

    # Time
    GET 'ti.me', NoQuery

    # TinyURL
    GET 'tinyurl.com', NoQuery

    # Tumblr
    GET 'springarden.tumblr.com', -> r {r.env[:query].has_key?('audio_file') ? [301, {'Location' => r.env[:query]['audio_file']}, []] : NoGunk[r]}
    
    # Twitch
    %w( api gql irc-ws.chat panels-images pubsub-edge www ).map{|h|Allow h + '.twitch.tv'}
    GET 'static.twitchcdn.net'

    # Twitter
    Allow 'twitter.com'
    Allow 'api.twitter.com'

    %w(bit.ly trib.al).map{|short| GET short, NoQuery }
    GET 't.co', -> r {r.parts[0] == 'i' ? r.deny : NoQuery[r]}

    Populate 'twitter.com', -> r {
      FileUtils.mkdir 'twitter'
      `cd ~/src/WebServer && git show -s --format=%B a3e600d66f2fd850577f70445a0b3b8b53b81e89`.split.map{|n|
        FileUtils.touch 'twitter/.' + n}}

    GET 'twitter.com', -> r {
      if cookie = r.env['HTTP_COOKIE']
        r.env['authorization'] = 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
        attrs = {}
        cookie.split(';').map{|attr|
          k,v = attr.split '='
          attrs[k] = v}
        if ctoken = attrs['ct0']
          r.env['x-csrf-token'] = ctoken
        end
        if gtoken = attrs['gt']
          r.env['x-guest-token'] = gtoken
        end
      end

      if !r.path || r.path == '/'
        subscriptions = Pathname.glob('twitter/.??*').map{|n|n.basename.to_s[1..-1]}
        r.env.delete :query
        r.env.delete 'QUERY_STRING'
        subscriptions.shuffle.each_slice(18){|sub|
          q = sub.map{|u|'from%3A' + u}.join('%2BOR%2B')
          apiURL = 'https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=' + q + '&vertical=default&count=40&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2CcameraMoment'
          apiURL.R(r.env).fetch intermediate: true}
        r.saveRDF.chrono_sort.graphResponse
      elsif r.path == '/feed'
        Pathname.glob('twitter/.??*').map{|n|n.basename.to_s[1..-1]}.shuffle.each_slice(18){|s|
          '//twitter.com/search'.R(r.env).fetch intermediate: true, noRDF: true,
                                                query: {vertical: :default, f: :tweets, q: s.map{|u|'from:' + u}.join('+OR+')}}
        r.saveRDF.chrono_sort.graphResponse
      elsif r.gunkURI
        r.deny
      elsif r.path.match? GlobChars
        r.nodeRequest
      elsif r.parts.size == 1 && !r.upstreamUI? && !%w(favicon.ico manifest.json search).member?(r.parts[0])
        user = r.parts[0]
        if user.match? /^\d+$/
          uid = user
        else
          URI.open('https://api.twitter.com/graphql/G6Lk7nZ6eEKd7LBBZw9MYw/UserByScreenName?variables=%7B%22screen_name%22%3A%22' + user + '%22%2C%22withHighlightedLabel%22%3Afalse%7D', r.headers) do |response|
            body = HTTP.decompress response.meta, response.read
            json = ::JSON.parse body
            uid = json['data']['user']['rest_id']
          end
        end
        apiURL = 'https://api.twitter.com/2/timeline/profile/' + uid + '.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&include_tweet_replies=false&userId=' + uid + '&count=20&ext=mediaStats%2CcameraMoment'
        apiURL.R(r.env).fetch intermediate: true
        r.saveRDF.chrono_sort.graphResponse
      else
        r.fetch
      end}

    # USAtoday
    GET 'rssfeeds.usatoday.com', NoQuery

    # Viglink
    GET 'redirect.viglink.com', GotoU

    # Vimeo
    GET 'f.vimeocdn.com'

    # WaPo
    GET 'www.washingtonpost.com', -> r {(r.parts[0]=='resizer' ? Resizer : NoGunk)[r]}

    # Weather
    Allow 'api.weather.com'
    Allow 'profile.wunderground.com'

    # WebMD
    GET 'img.webmd.com', NoJS

    # Wiley
    Cookies 'agupubs.onlinelibrary.wiley.com'

    # Wix
    GET 'static.parastorage.com'

    # WordPress
    %w(i0 i1 i2 s0 s1 s2).map{|h| GET h + '.wp.com' }

    # WSJ
    %w(images m s).map{|h| GET h + '.wsj.net' }

    # Yahoo!
    %w(finance.yahoo.com
          news.yahoo.com
       sg.news.yahoo.com
media-mbst-pub-ue1.s3.amazonaws.com
).map{|host|
      GET host, NoJS}

    GET 's.yimg.com', -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        NoJS[r]
      end}

    # Yelp
    GET 'www.yelp.com', -> r {r.env[:query]['redirect_url'] ? [301, {'Location' => r.env[:query]['redirect_url']},[]] : r.fetch}

    # YouTube
    Cookies 'm.youtube.com'
    Allow 'www.youtube.com'
    GET 'youtube.com', -> r {[301, {'Location' =>  'https://www.youtube.com' + r.path + r.qs}, []]}
    GET 'm.youtube.com', -> r {%w(channel feed playlist results user watch watch_comment yts).member?(r.parts[0]) ? r.upstreamUI.fetch : r.deny}
    GET 'img.youtube.com', NoJS

    GET 'www.youtube.com', -> r {
      fn = r.parts[0]
      if %w{attribution_link redirect}.member? fn
        [301, {'Location' =>  r.env[:query]['q'] || r.env[:query]['u']}, []]
      elsif !fn
        [301, {'Location' => '/feed/subscriptions'}, []]
      elsif r.env[:query]['allow'] == ServerKey
        r.fetch
      elsif %w(browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist results signin user watch watch_videos yts).member? fn
        r.upstreamUI.fetch
      elsif ENV.has_key? 'GOOGLE'
        r.fetch
      else
        r.deny
      end}

    POST 'www.youtube.com', -> r {
      if r.parts.member? 'stats'
        r.denyPOST
      elsif r.env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/i
        r.POSTthru
      else
        r.denyPOST
      end}

    # ZeroHedge
    Allow 'talk.zerohedge.com'
    GET 'www.zerohedge.com', Fetch

    # Zillow
    Allow 'www.zillow.com'

  end

  def AP doc
    doc.css('script').map{|script|
      script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data|
        data = data[0]
        data = data[0..-2] if data[-1] == ';'
        Webize::HTML.webizeHash(::JSON.parse data){|hash|
          # resource identifier
          id = '#ap_' + Digest::SHA2.hexdigest(rand.to_s)

          # image-post resources
          if base = (hash.delete 'gcsBaseUrl')
            hash['type'] = Post.R
            if fmt = (hash.delete 'imageFileExtension')
              if sizes = (hash.delete 'imageRenderedSizes')
                sizes.map{|size|
                  yield id, Image.R, (base + size.to_s + fmt).R}
              end
            end
          end

          # massage data
          %w(contentType embedRatio ignoreClickOnElements order socialEmbeds shortId sponsored videoRenderedSizes).map{|p| hash.delete p}
          hash.map{|p, o|
            p = MetaMap[p] || p
            o = Webize::HTML.clean o, self if p == Content && o.class == String
            o = Post.R if p == Type && o == 'article'

            # emit triples
            unless p == :drop
              case o.class.to_s
              when 'Array'
                o.flatten.map{|o|
                  yield id, p, o unless o.class == Hash}
              when 'Hash'
              else
                yield id, p, o
              end
            end
          }}}}
  end

  def CityData doc
    doc.css("table[id^='post']").map{|post|
      subject = join '#' + post['id']
      yield subject, Type, Post.R
      post.css('a.bigusername').map{|user|
        yield subject, Creator, (join user['href'])
        yield subject, Creator, user.inner_text }
      post.css("div[id^='post_message']").map{|content|
        yield subject, Content, Webize::HTML.clean(content.inner_html, self)}
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

  GHgraph = /__gh__coreData.content=(.*?);?\s*__gh__coreData.content.bylineFormat/m
  def GateHouse doc
    doc.css('script').map{|script|
      if data = script.inner_text.gsub(/[,\s]+\]/m,']').match(GHgraph)
        graph = ::JSON.parse data[1]
        Webize::HTML.webizeHash(graph){|h|
          if h['type'] == 'gallery'
            h['items'].map{|i|
              subject = i['link']
              yield subject, Type, Post.R
              yield subject, Image, subject.R
              yield subject, Abstract, CGI.escapeHTML(i['caption'])
            }
          end}
      end}
  end

  def GitHub doc
    base = 'https://github.com'
    doc.css('div.comment').map{|comment|
      if ts = comment.css('.js-timestamp')[0]
        subject = ts['href'] || self
        yield subject, Type, Post.R
        if body = comment.css('.comment-body')[0]
          yield subject, Content, Webize::HTML.clean(body.inner_html, self)
        end
        if time = comment.css('[datetime]')[0]
          yield subject, Date, time['datetime']
        end
        if author = comment.css('.author')[0]
          yield subject, Creator, (base + author['href']).R
          yield subject, Creator, author.inner_text
        end
        yield subject, To, self
        comment.remove
      end
    }
  end

  def Gitter doc
    doc.css('.chat-item').map{|msg|
      
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
          yield subject, Content, s.inner_html
          rc.remove
        end
      end}
  end

  def HackerNews doc
    base = 'https://news.ycombinator.com/'
    doc.css('div.comment').map{|comment|
      post = comment.parent
      date = post.css('.age > a')[0]
      subject = base + date['href']
      yield subject, Type, Post.R
      yield subject, Content, comment.inner_html
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
        env[:links][:prev] ||= '/graphql/query/' + HTTP.qs({query_hash: :e769aa130647d2354c40ea6a439bfc08, rdf: :rdf, variables: {id: uid, first: 12, after: end_cursor}.to_json}) if uid && end_cursor
      end
      yield ('https://www.instagram.com/' + h['username']).R, Type, Person.R if h['username']
      if h['shortcode']
        s = 'https://www.instagram.com/p/' + h['shortcode']
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
          yield s, Abstract, CGI.escapeHTML(text).split(' ').map{|t|
                if match = (t.match /^@([a-zA-Z0-9._]+)(.*)/)
                  "<a id='u#{Digest::SHA2.hexdigest rand.to_s}' class='uri' href='https://www.instagram.com/#{match[1]}'>#{match[1]}</a>#{match[2]}"
                else
                  t
                end}.join(' ')
        end rescue nil
      end
    }
  end

  def LWN doc
    doc.css()
  end

  def Outline tree
    subject = tree['data']['article_url']
    yield subject, Type, Post.R
    yield subject, Title, tree['data']['title']
    yield subject, To, ('//' + tree['data']['domain']).R
    yield subject, Content, (Webize::HTML.clean tree['data']['html'], self)
    yield subject, Image, tree['data']['meta']['og']['og:image'].R
  end

  def RedditJSON tree
    puts tree.keys
  end

  def TwitterHTML doc, &b

    # page pointer
    doc.css('.stream-container').map{|stream|
      user = parts[0]
      if user && position = stream['data-min-position']
        env[:links][:prev] = '/i/profiles/show/' + user + '/timeline/tweets?include_available_features=1&include_entities=1&max_position=' + position + '&reset_error_state=false&rdf&view=table&sort=date'
      end}

    # tweets
    %w{grid-tweet tweet}.map{|tweetclass|
      doc.css('.' + tweetclass).map{|tweet|
        s = 'https://twitter.com' + (tweet.css('.js-permalink').attr('href') || tweet.attr('data-permalink-path') || '')
        yield s, Type, (SIOC + 'MicroblogPost').R
        yield s, To, 'https://twitter.com'.R

        authorName = if b = tweet.css('.username b')[0]
                       b.inner_text
                     else
                       s.R.parts[0]
                     end
        author = ('https://twitter.com/' + authorName).R
        yield s, Creator, author

        ts = (if unixtime = tweet.css('[data-time]')[0]
              Time.at(unixtime.attr('data-time').to_i)
             else
               Time.now
              end).iso8601
        yield s, Date, ts

        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'l' + Digest::SHA2.hexdigest(rand.to_s))
            a.set_attribute('href', 'https://twitter.com' + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, Webize::HTML.clean(content.inner_html, self).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
        end

        if img = tweet.attr('data-resolved-url-large')
          yield s, Image, img.to_s.R
        end
        tweet.css('img').map{|img|
          yield s, Image, img.attr('src').to_s.R}

        tweet.css('.PlayableMedia-player').map{|player|
          player['style'].match(/url\('([^']+)'/).yield_self{|url|
            yield s, Video, url[1].sub('pbs','video').sub('_thumb','').sub('jpg','mp4')
          }}}}

    %w(link[rel="alternate"] meta[name="description"] title body).map{|sel|
      doc.css(sel).remove}
  end

  def TwitterHTMLinJSON tree, &b
    # page pointer
    if position = tree['min_position']
      env[:links][:prev] = '/i/profiles/show/' + parts[3] + '/timeline/tweets?include_available_features=1&include_entities=1&max_position=' + position + '&reset_error_state=false&rdf&view=table&sort=date'
    end
    # tweets
    if html = tree['items_html']
      TwitterHTML Nokogiri::HTML.fragment(html), &b
    end
  end

  def TwitterJSON tree, &b
    if objects = tree['globalObjects']
      if tweets = objects['tweets']
        tweets.map{|id, tweet|
          #puts ::JSON.pretty_generate tweet
          id = tweet['id_str']
          username = tweet['in_reply_to_screen_name']
          user = 'https://twitter.com/' + username if username
          uri =  (user || '#') + '/status/' + id
          yield uri, Type, (SIOC + 'MicroblogPost').R
          yield uri, To, 'https://twitter.com'.R
          yield uri, Date, Time.parse(tweet['created_at']).iso8601
          yield uri, Creator, user.R if user
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
  end

  def UHub doc
    doc.css('.pager-next > a[href]').map{|n| env[:links][:next] ||= n['href'] }
    doc.css('.pager-previous > a[href]').map{|p| env[:links][:prev] ||= p['href'] }
  end

  def YouTubeHTML doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
