module Webize
  module HTML
    class Reader

      SiteGunk = {'www.google.com' => %w(div.logo h1 h2),
                  'www.bostonmagazine.com' => %w(a[href*='scrapertrap'])}

      # HTML -> RDF methods
      Triplr = {
        'apnews.com' => :AP,
        'boards.4channel.org' => :FourChannel,
        'github.com' => :GitHub,
        'lwn.net' => :LWN,
        'news.ycombinator.com' => :HackerNews,
        'twitter.com' => :Twitter,
        'universalhub.com' => :UHub,
        'www.aliexpress.com' => :AX,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :Instagram,
        'www.patriotledger.com' => :GateHouse,
        'www.providencejournal.com' => :GateHouse,
        'www.universalhub.com' => :UHub,
        'www.youtube.com' => :YouTube,
      }

    end
  end
  module JSON

    # JSON -> RDF methods
    Triplr = {
      'gateway.reddit.com' => :Reddit,
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
    SiteDir  = (Pathname.new __dir__).relative_path_from Pathname.new Dir.pwd
    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteGIF = SiteDir.join('site.gif').read
    SiteCSS = SiteDir.join('site.css').read #+ SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
  end
  module HTTP

    CDNhost = /\.(akamai(hd)?|amazonaws|.*cdn|cloud(f(lare|ront)|inary)|fastly|github|googleapis|netdna.*)\.(com|io|net)$/
    CookieHost = /\.bandcamp\.com$/
    DesktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/888.38 (KHTML, like Gecko) Chrome/80.0.3888.80 Safari/888.38'
    DynamicImgHost = /(noaa|weather)\.gov$/

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302,
                          {'Location' => 'https://' + parts[-1] #+ '?allow='+ServerKey
                          }, []] : NoJS[r]
      else
        NoJS[r]
      end}

    # ABC
    GET 'abcnews.go.com'
    GET 's.abcnews.com', NoJS

    # ACM
    Cookies 'dl.acm.org'

    # Adobe
    Allow 'entitlement.auth.adobe.com'
    Allow 'sp.auth.adobe.com'
    GET 'entitlement.auth.adobe.com', Desktop
    GET 'sp.auth.adobe.com', Desktop

    # AliBaba
    %w(ae01.alicdn.com
     assets.alicdn.com
          i.alicdn.com
  chuwi.aliexpress.com
s.click.aliexpress.com
    www.aliexpress.com
).map{|host|
      GET host}

    # Amazon
    AmazonReferer = -> r {r.env['HTTP_REFERER']&.match(/(amazon|imdb)\.com/) && NoGunk[r] || r.deny}

    GET 'amazon.com'
    GET 'www.amazon.com'
    GET 'images-na.ssl-images-amazon.com', AmazonReferer
    GET 'm.media-amazon.com', AmazonReferer

    # Apple
    %w{amp-api.music api.music audio-ssl.itunes embed.music itunes js-cdn.music music www xp}.map{|h|
      host = h + '.apple.com'
      Allow host
      GET host, Desktop}

    # Appspot
    %w(xmountwashington).map{|h| Allow h + '.appspot.com'}

    # Anvato
    Allow 'tkx.apis.anvato.net'

    # Atlassian
    Allow 'zerotier.atlassian.net'

    # Balamii
    Allow 'balamii-parse.herokuapp.com'
    Allow 'player.balamii.com'

    # Blocks
    GET 'bl.ocks.org', Desktop

    # Bloomberg
    Cookies 'www.bloomberg.com'

    # Boston Globe
    GET 'bos.gl', -> r {r.fetch scheme: :http}
    GET 'bostonglobe-prod.cdn.arcpublishing.com', Resizer
    %w(www).map{|host| GET host + '.boston.com', NoJS}
    %w(apps www www3).map{|host| GET host + '.bostonglobe.com', NoJS}

    # Brightcove
    %w(
edge.api.brightcove.com
players.brightcove.net
secure.brightcove.com
).map{|h|
      Allow h
        GET h, Desktop}

    # Brightspot
    GET 'ca-times.brightspotcdn.com', GoIfURL

    # BusinessWire
    GET 'cts.businesswire.com', GoIfURL

    # BuzzFeed
    GET 'img.buzzfeed.com', NoJS

    # CBS
    GET 'www.cbsnews.com', NoJS

    # CircleCI
    GET 'circleci.com', -> r {r.parts[0] == 'blog' ? r.fetch : r.deny}

    # Cloudflare
    GET 'cdnjs.cloudflare.com', Fetch

    # Complex
    %w(images www).map{|h| GET h + '.complex.com' }

    # Costco
    Allow 'www.costco.com'

    # CNet
    GET 'www.cnet.com'

    # CNN
    %w(cdn edition rss www www.i.cdn).map{|host| Allow host + '.cnn.com' }
    GET 'dynaimage.cdn.cnn.com', GotoBasename

    # DartSearch
    GET 'clickserve.dartsearch.net', -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # DuckDuckGo
    GET 'duckduckgo.com', -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.fetch}
    GET 'proxy.duckduckgo.com', -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.fetch}

    # eBay
    Allow 'www.ebay.com'
    %w(ebay.com
   www.ebay.com
    ir.ebaystatic.com
thumbs.ebaystatic.com).map{|host| GET host }

    GET 'i.ebayimg.com', -> r {r.basename.match?(/s-l(64|96|200|225).jpg/) ? [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []] : r.fetch}
    GET 'rover.ebay.com', -> r {r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # Economist
    GET 'www.economist.com'

    # Embedly
    GET 'cdn.embedly.com', Desktop

    # ESPN
    %w(api-app broadband media.video-cdn secure site.api site.web.api watch.auth.api watch.graph.api www).map{|h|
      Allow h + '.espn.com' }

    %w(a a1 a2 a3 a4).map{|a|
      GET a + '.espncdn.com' }

    # Facebook
    if ENV.has_key?('FACEBOOK')
      GET 'www.facebook.com', Fetch
      %w(facebook.com business.facebook.com edge-chat.facebook.com m.facebook.com static.xx.fbcdn.net www.facebook.com).map{|host| Allow host }
    end

    %w(l.facebook.com lm.facebook.com).map{|host|
      GET host, GotoU}

    # FDroid
    Cookies 'f-droid.org'

    # Flickr
    GET 'combo.staticflickr.com', -> r {r.path=='/zz/combo' ? r.fetch : NoGunk[r]}

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    # FoxNews
    if ENV.has_key? 'FOX'
      #Cookies 'video.foxnews.com'
    end

    # Gfycat
    GET 'gfycat.com'
    GET 'thumbs.gfycat.com'

    # GitHub
    GET 'api.github.com', -> r {r.desktopUI.fetch}
    GET 'github.com'
    %w(avatars0 avatars1 avatars2 avatars3 raw).map{|h|
      GET h + '.githubusercontent.com', NoJS }

    # GitLab
    GET 'assets.gitlab-static.net', Fetch

    # Gitter
    Allow 'gitter.im'
    Allow 'ws.gitter.im'

    # Google
    unless ENV.has_key? 'DEGOOGLE'

      (1..4).map{|i| GET "#{i}.bp.blogspot.com" }
      (1..4).map{|i| Allow "clients#{i}.google.com" } if ENV.has_key? 'GOOGLE'
      (0..3).map{|i| GET "khms#{i}.google.com" }
      (0..3).map{|i| GET "encrypted-tbn#{i}.gstatic.com" }
      %w(books docs drive images maps news scholar).map{|h|GET h + '.google.com' }
      %w(ajax maps www).map{|h|GET h + '.googleapis.com' }
      %w(maps ssl www).map{|h| GET h + '.gstatic.com' }

      Cookies 'www.google.com'
      GET 'google.com', -> r {[301, {'Location' => 'https://www.google.com' + r.env['REQUEST_URI'] }, []]}
      GET 'www.google.com', -> r {
        case r.path
        when /^.images/
          NoJS[r]
        when /^.maps/
          r.desktopUI.fetch
        when /^.search/
          q = r.env[:query]['q']
          q && q.match?(/^(https?:|l(ocalhost)?(:8000)?)\//) && [301,{'Location'=>q.sub(/^l/,'http://l')},[]] || r.fetch
        when '/url'
          GotoURL[r]
        else
          (ENV.has_key?('BARNDOOR') || ENV.has_key?('GOOGLE')) ? r.fetch : r.deny
        end}
    end

    # Guardian
    GET 'i.guim.co.uk'
    GET 'www.theguardian.com'

    # iHeart
    Allow 'us.api.iheart.com'
    Allow 'www.iheart.com'
    GET 'i.iheart.com'

    # Imgur
    Allow 'api.imgur.com'
    %w(i.imgur.com i.stack.imgur.com).map{|host| GET host, Desktop }

    %w(imgur.com
     m.imgur.com
     s.imgur.com
).map{|host| GET host}

    # Inrupt
    Allow 'dev.inrupt.net'

    # Instagram
    GET 'l.instagram.com', GotoU
    GET 'www.instagram.com', RootIndex

    Populate 'www.instagram.com', -> r {
      base = 'com/instagram/'
      FileUtils.mkdir_p base
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

    %w(ig).map{|host| GET host, IG}

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
    GET 'thumb.cloud.mail.ru', NoJS

    # MassLive
    GET 'i.masslive.com', Resizer

    # Mastodon
    %w(
assets.octodon.social
     drive.nya.social
files.mastodon.social
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
    CDNscripts 'nextdoor.com'

    # NOAA
    GET 'www.tsunami.gov', Desktop

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
         end).indexRDF.graphResponse
      end}

    # Patch
    GET 'patch.com', NoQuery

    # Patriot Ledger
    GET 'www.patriotledger.com', -> r {NoGunk[r.env[:query].has_key?('template') ? r.desktopUI : r]}

    # Rarbg
    Allow 'rarbg.to'
    GET 'rarbg.to', -> r {r.desktopUI.fetch}

    # Reddit
    GotoReddit = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path + r.qs}, []]}

    Populate 'www.reddit.com', -> r {FileUtils.mkdir_p 'com/reddit';'Dorchester+Rad_Decentralization+SOLID+StallmanWasRight+boston+dancehall+darknetplan+fossdroid+massachusetts+roxbury+selfhosted+shortwave'.split('+').map{|n| FileUtils.touch 'com/reddit/.' + n}}
    %w(reddit-uploaded-media.s3-accelerate.amazonaws.com v.redd.it).map{|h| Allow h }
    %w(gateway gql oauth www).map{|h| Allow h + '.reddit.com' }
    %w(www.redditmedia.com).map{|host| GET host, Desktop }
    %w(np.reddit.com reddit.com).map{|host| GET host, GotoReddit }

    Reddit = -> r {
      r.chrono_sort if r.parts[-1] == 'new' || r.path == '/'       # chrono-sort new posts
      r = ('/r/'+ Pathname.glob('com/reddit/.??*').map{|n|n.basename.to_s[1..-1]}.join('+')+'/new').R r.env if r.path == '/' # subscriptions
      r.desktopUI if r.parts[-1] == 'submit'                       # upstream UI for post submission
      options = {suffix: '.rss'} if r.ext.empty? && !r.upstreamUI? # upstream-representation preference
      r.env[:links][:prev] = 'https://old.reddit.com' + r.path + r.qs # page pointers
      r.env[:links][:up] = r.dirname unless r.path == '/'
      r.fetch options}

    GET 'www.reddit.com', Reddit

    GET 'old.reddit.com', -> r {
      r.desktopUI.fetch.yield_self{|status,head,body|
        if status.to_s.match?(/^30/) || ENV.has_key?('BARNDOOR')
          [status, head, body]
        else
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

    # Responsys
    GET 'static.cdn.responsys.net', NoJS

    # Reuters
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
).map{|h| Allow h; GET h, Desktop}
    GET 'soundcloud.com', -> r {r.path=='/' ? RootIndex[r] : Desktop[r]}

    # Spotify
    %w(api apresolve embed guc-dealer guc-spclient open spclient.wg).map{|h|
      host = h + '.spotify.com'
      Allow host; GET host, Desktop} if ENV.has_key? 'SPOTIFY'

    # StarTribune
    Allow 'comments.startribune.com'

    # Tableau
    Allow 'public.tableau.com'
    GET   'public.tableau.com', Desktop

    # Technology Review
    GET 'cdn.technologyreview.com', NoQuery

    # Twitch
    GET 'www.twitch.tv', Desktop
    %w(api.twitch.tv
         gql.twitch.tv
         www.twitch.tv
).map{|h|Allow h} if ENV.has_key? 'TWITCH'

    # Twitter
    Allow 'api.twitter.com'
    Allow 'proxsee.pscp.tv'

    GotoTwitter = -> r {[301,{'Location' => 'https://twitter.com' + r.path },[]]}
    %w(mobile.twitter.com tweettunnel.com www.twitter.com).map{|host| GET host, GotoTwitter }
    GET 't.co', -> r {r.parts[0] == 'i' ? r.deny : NoQuery[r]}
    GET 'trib.al', NoQuery

    Populate 'twitter.com', -> r {
      FileUtils.mkdir_p 'com/twitter'
      `cd ~/src/WebServer && git show -s --format=%B a3e600d66f2fd850577f70445a0b3b8b53b81e89`.split.map{|n|
        FileUtils.touch 'com/twitter/.' + n}}

    GET 'twitter.com', -> r {
      r.desktopUA
      if !r.path || r.path == '/'
        r.env[:links][:feed] = '/feed'
        RootIndex[r]
      elsif r.path == '/feed'
        Pathname.glob('com/twitter/.??*').map{|n|n.basename.to_s[1..-1]}.shuffle.each_slice(18){|s|
          '/search'.R(r.env).fetch intermediate: true,
                                   noRDF: true,
                                   query: {vertical: :default, f: :tweets, q: s.map{|u|'from:'+u}.join('+OR+')}}
        r.chrono_sort
        r.indexRDF.graphResponse
      elsif r.parts[-1] == 'status'
        r.cachedGraph
      elsif r.gunkURI
        r.deny
      else
        r.env[:links][:up]    = '/' if r.parts.size == 1
        r.env[:links][:up]    = '/' + r.parts[0] if r.path.match? /\/status\/\d+\/?$/
        r.env[:links][:media] = '/' + r.parts[0] + '/media' unless %w(media search).member? r.parts[1]
        r.fetch noRDF: true
      end}

    # Ubuntu
    GET 'us.archive.ubuntu.com', Desktop

    # Viglink
    GET 'redirect.viglink.com', GotoU

    # Vimeo
    %w(f.vimeocdn.com player.vimeo.com vimeo.com).map{|host| GET host, Desktop }

    # VRT
    CDNscripts 'www.vrt.be'
    Allow 'media-services-public.vrt.be'

    # WaPo
    GET 'www.washingtonpost.com', -> r {(r.parts[0]=='resizer' ? Resizer : NoJS)[r]}

    # WBUR
    CDNscripts 'www.wbur.org'

    # Weather
    Allow 'api.weather.com'
    Allow 'profile.wunderground.com'

    # WCVB
    GET 'www.wcvb.com', Desktop

    # WGBH
    GET 'wgbh.brightspotcdn.com', GoIfURL

    # Wiley
    Cookies 'agupubs.onlinelibrary.wiley.com'

    # Wix
    GET 'static.parastorage.com'
    GET 'static.wixstatic.com'

    # WordPress
    %w(
public-api.wordpress.com
videos.files.wordpress.com
).map{|host| GET host, Fetch}
    (0..7).map{|i| GET "i#{i}.wp.com", NoQuery}
    (0..2).map{|i| GET "s#{i}.wp.com"}

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
    GET 's.ytimg.com', Desktop
    GET 'www.youtube-nocookie.com', Desktop
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

    # Zillow
    Allow 'www.zillow.com'

  end

  def AP doc
    doc.css('script').map{|script|
      script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data|
        data = data[0]
        data = data[0..-2] if data[-1] == ';'
        json = ::JSON.parse data
        yield self, Content, HTML.render(HTML.keyval (Webize::HTML.webizeHash json), env)}}
  end

  def AX doc
    doc.css('script').map{|script|
      script.inner_text.scan(/"(http[^"]+\.(jpg|png|webp)[^"]*)"/){|img| yield self, Image, img[0].R }
      script.inner_text.scan(/"(http[^"]+\.(mp4|webm)[^"]*)"/){|img| yield self, Video, img[0].R }}
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

  def FourChannel doc
  end

  GHgraph = /__gh__coreData.content=(.*?)\s*__gh__coreData.content.bylineFormat/m
  def GateHouse doc
    doc.css('script').map{|script|
      if data = script.inner_text.match(GHgraph)
        graph = ::JSON.parse data[1][0..-2]
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
          yield subject, Content, body.inner_html
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

  def Instagram doc, &b
    doc.css('script').map{|script|
      if script.inner_text.match? IGgraph
        InstagramJSON ::JSON.parse(script.inner_text.sub(IGgraph,'')[0..-2]), &b
      end}
  end

  def InstagramJSON tree, &b
    Webize::HTML.webizeHash(tree){|h|
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
                  "<a href='https://www.instagram.com/#{match[1]}'>#{match[1]}</a>#{match[2]}"
                else
                  t
                end}.join(' ')
        end rescue nil
      end}
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

  def Reddit tree
    puts tree.keys
  end

  def Twitter doc
    %w{grid-tweet tweet}.map{|tweetclass|
      doc.css('.' + tweetclass).map{|tweet|
        s = 'https://twitter.com' + (tweet.css('.js-permalink').attr('href') || tweet.attr('data-permalink-path') || '')
        yield s, Type, Post.R
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

  def UHub doc
    doc.css('.pager-next > a[href]').map{|n| env[:links][:next] ||= n['href'] }
    doc.css('.pager-previous > a[href]').map{|p| env[:links][:prev] ||= p['href'] }
  end

  def YouTube doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
