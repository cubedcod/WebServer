module Webize
  module HTML
    class Reader

      SiteGunk = {'www.google.com' => %w(div.logo h1 h2),
                  'www.bostonmagazine.com' => %w(a[href*='scrapertrap'])}

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
    Triplr = {
      'gateway.reddit.com' => :Reddit,
      'outline.com' => :Outline,
      'outlineapi.com' => :Outline,
      'www.youtube.com' => :YouTubeJSON,
    }
  end
end
class WebResource
  module URIs
    SiteDir  = (Pathname.new __dir__).relative_path_from Pathname.new Dir.pwd

    FeedIcon = SiteDir.join('feed.svg').read
    SiteGIF = SiteDir.join('site.gif').read
    SiteCSS = SiteDir.join('site.css').read + SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
  end
  module HTTP

    CDNhost = /\.(amazonaws|.*cdn|cloud(f(lare|ront)|inary)|fastly|googleapis|netdna.*)\.(com|net)$/
    DesktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/888.38 (KHTML, like Gecko) Chrome/80.0.3888.80 Safari/888.38'

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
    GET 'abcnews.go.com', NoJS
    GET 's.abcnews.com', NoJS

    # ACM
    Cookies 'dl.acm.org'

    # AliBaba
    %w(ae01.alicdn.com
     assets.alicdn.com
          i.alicdn.com
  chuwi.aliexpress.com
s.click.aliexpress.com
    www.aliexpress.com
).map{|host|
      GET host, NoGunk}

    # Amazon
    AmazonMedia = -> r {%w(css jpg mp4 png webm webp svg).member?(r.ext.downcase) && r.env['HTTP_REFERER']&.match(/(amazon|imdb)\.com/) && r.fetch || r.deny}
    if ENV.has_key? 'AMAZON'
      %w(            amazon.com
images-na.ssl-images-amazon.com
               s3.amazonaws.com
                 www.amazon.com).map{|h|Allow h}
    else
      GET 'amazon.com', NoJS
      GET 'www.amazon.com', NoJS
      GET 'images-na.ssl-images-amazon.com', AmazonMedia
      GET 'm.media-amazon.com', AmazonMedia
    end

    # Anvato
    Allow 'tkx.apis.anvato.net'

    # Ars Technica
    GET 'cdn.arstechnica.net', NoJS

    # Boston Globe
    GET 'bos.gl', -> r {r.fetch scheme: :http}
    GET 'www3.bostonglobe.com', Fetch
    GET 'bostonglobe-prod.cdn.arcpublishing.com', Resizer

    # Brightcove
    Allow 'players.brightcove.net'
    Allow 'edge.api.brightcove.com'
    Allow 'secure.brightcove.com'
    GET 'edge.api.brightcove.com', Fetch

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
    Allow 'cdnjs.cloudflare.com'

    # Costco
    Allow 'www.costco.com'

    # CNet
    GET 'www.cnet.com', NoJS

    # CNN
    %w(cdn edition www).map{|host|
      Allow host + '.cnn.com'}
    GET 'dynaimage.cdn.cnn.com', GotoBasename

    # DartSearch
    GET 'clickserve.dartsearch.net', -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # DuckDuckGo
    GET 'duckduckgo.com', -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.fetch}
    GET 'proxy.duckduckgo.com', -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.fetch}

    # eBay
    Allow 'ebay.com'
    Allow 'www.ebay.com'
    Allow 'ir.ebaystatic.com'
    GET 'i.ebayimg.com', -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.fetch
      end}
    GET 'rover.ebay.com', -> r {
      r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # embedly
    GET 'cdn.embedly.com', Desktop

    # Facebook
    FBgunk = %w(common connect pages_reaction_units security tr)

    if ENV.has_key?('FACEBOOK')
      %w(facebook.com
business.facebook.com
       m.facebook.com
     www.facebook.com
).map{|host|
        Allow host
        GET host, -> r {FBgunk.member?(r.parts[0]) ? r.deny : NoGunk[r]}}
    end

    %w(l.facebook.com
      lm.facebook.com).map{|host|
      GET host, GotoU}

    # Flickr
    GET 'combo.staticflickr.com', -> r {r.path=='/zz/combo' ? r.fetch : NoGunk[r]}

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    # FSDN
    if ENV.has_key?('FSDN')
      GET 'a.fsdn.com', NoGunk
    else
      GET 'a.fsdn.com', NoJS
    end

    # Gfycat
    GET 'gfycat.com', NoGunk
    GET 'thumbs.gfycat.com', NoGunk

    # GitHub
    GET 'github.com', NoGunk

    # GitLab
    GET 'assets.gitlab-static.net', Fetch

    # Google
    %w(ajax.googleapis.com
          books.google.com
     developers.google.com
           docs.google.com
          drive.google.com
encrypted-tbn0.gstatic.com
encrypted-tbn1.gstatic.com
encrypted-tbn2.gstatic.com
encrypted-tbn3.gstatic.com
         groups.google.com
         images.google.com
             kh.google.com
           maps.google.com
       maps.googleapis.com
          maps.gstatic.com
        scholar.google.com
           ssl.gstatic.com
    storage.googleapis.com
           www.gstatic.com
).map{|h| Allow h }

    if ENV.has_key? 'GOOGLE'
    %w(
      adservice.google.com
       accounts.google.com
android.clients.google.com
    android.googleapis.com
           apis.google.com
         chrome.google.com
       clients1.google.com
       clients2.google.com
       clients4.google.com
       clients5.google.com
      feedproxy.google.com
      feeds.feedburner.com
                google.com
             id.google.com
             kh.google.com
           mail.google.com
           news.google.com
            ogs.google.com
           play.google.com
       play.googleapis.com
 suggestqueries.google.com
 tpc.googlesyndication.com
            www.google.com
  www.googleadservices.com
        www.googleapis.com
         www.recaptcha.net
).map{|host|
      Allow host}
    else
      GET 'google.com', -> r {[301,{'Location' => 'https://www.google.com' + r.env['REQUEST_URI'] },[]]}
      GET 'news.google.com', NoJS
      GET 'www.google.com', -> r {
        case r.path
        when /^.(aclk)?$/
          r.fetch
        when /^.maps/
          Desktop[r]
        when '/search'
          if r.env[:query]['q']&.match? /^(https?:\/\/|l(:8000|\/)|localhost|view-source)/
            [301, {'Location' => r.env[:query]['q'].sub(/^l/,'http://l')}, []]
          else
            r.fetch
          end
        when /^.(images|.*photos)/
          NoJS[r]
        when '/url'
          GotoURL[r]
        else
          r.deny
        end}
      GET 'www.googleadservices.com', -> r {r.path=='/pagead/aclk' && r.env[:query].has_key?('adurl') && [301, {'Location' =>  r.env[:query]['adurl']}, []] || r.deny}
    end

    # Guardian
    GET 'i.guim.co.uk', NoJS
    GET 'www.theguardian.com', NoJS

    # Imgur
    %w(imgur.com
     i.imgur.com
     m.imgur.com
     s.imgur.com
).map{|host|
      GET host, NoGunk}

    Cookies 'imgur.com'

    POST 'imgur.com', -> r {
      if r.path == '/signin'
        r.POSTthru
      else
        r.denyPOST
      end}

    # Inrupt
    Allow 'dev.inrupt.net'

    # Instagram
    GET 'l.instagram.com', GotoU
    GET 'www.instagram.com', RootIndex

    IG  =  -> r {             [301, {'Location' => 'https://www.instagram.com'  + r.path},     []]         }
    IG0 =  -> r {r.parts[0] ? [301, {'Location' => 'https://www.instagram.com/' + r.parts[0]}, []] : r.deny}
    IG1 =  -> r {r.parts[1] ? [301, {'Location' => 'https://www.instagram.com/' + r.parts[1]}, []] : r.deny}

    %w(ig).map{|host| GET host, IG}

    %w(
deskgram.cc deskgram.net
graphixto.com
instapuma.com
picpanzee.com
saveig.org
www.pictosee.com
www.toopics.com
).map{|host| GET host, IG0}

    %w(
insee.me
jolygram.com
pikdo.net
piknu.com
publicinsta.com
www.pictame.com
zoopps.com
).map{|host| GET host, IG1}

    # Linkedin
    GET 'media.licdn.com', NoJS
    GET 'www.linkedin.com', NoJS

    # Little Free Library
    Allow 'littlefreelibrary.secure.force.com'

    # Mail.ru
    GET 'cloud.mail.ru', NoGunk
    GET 'img.imgsmail.ru', NoGunk
    GET 's.mail.ru', NoGunk
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
    GET 'medium.com', -> r {r.env[:query].has_key?('redirecturl') ? [301, {'Location' => r.env[:query]['redirecturl']}, []] : r.fetch}

    # Meetup
    Allow 'www.meetup.com'

    # Meredith
    GET 'imagesvc.meredithcorp.io', GoIfURL

    # Microsoft
    GET 'www.bing.com', NoJS
    GET 'www.msn.com', NoJS

    # Mixcloud
    Allow 'm.mixcloud.com'
    Allow 'www.mixcloud.com'

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

    # NYTimes
    %w(cooking.nytimes.com
           www.nytimes.com).map{|host|
      GET host, NoJS}

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

    # Reddit
    %w(gateway gql oauth www).map{|host|
      Allow host + '.reddit.com'
      GET host, NoGunk}

    GotoReddit = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path + r.qs}, []]}
    GET 'old.reddit.com', GotoReddit
    GET 'reddit.com', GotoReddit
    GET 'www.redditmedia.com', Desktop
    Allow 'reddit-uploaded-media.s3-accelerate.amazonaws.com'

    GET 'www.reddit.com', -> r {
      if r.path == '/'
        r = ('/r/'+'com/reddit/www/r/*/.sub*'.R.glob.map(&:dir).map(&:basename).join('+')+'/new').R r.env
        r.chrono_sort
      end
      r.desktopUI if r.parts[-1] == 'submit'
      options = {suffix: '.rss'} if r.ext.empty? && !r.upstreamUI? # upstream representation-preference
      depth = r.parts.size
      r.env[:links][:up] = if [3,6].member? depth
                             r.dirname
                           elsif 5 == depth
                             '/' + r.parts[0..1].join('/')
                           else
                             '/'
                           end
      r.fetch options}

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
    GET 'cdn.shopify.com', NoGunk

    # SkimResources
    GET 'go.skimresources.com', GotoURL

    # Soundcloud
    GET 'gate.sc', GotoURL
    GET 'soundcloud.com', -> r {r.path=='/' ? RootIndex[r] : Desktop[r]}
    GET 'w.soundcloud.com', Desktop
    %w(api-auth.soundcloud.com
       api-mobi.soundcloud.com
     api-mobile.soundcloud.com
         api-v2.soundcloud.com
     api-widget.soundcloud.com
            api.soundcloud.com
                soundcloud.com
         secure.soundcloud.com
              w.soundcloud.com
).map{|h|Allow h}

    # Spotify
    %w(embed open).map{|host|
      Allow host+'.spotify.com'
      GET host+'.spotify.com', Desktop}

    # StarTribune
    Allow 'comments.startribune.com'

    # Tableau
    Allow 'public.tableau.com'
    GET   'public.tableau.com', Desktop

    # Technology Review
    GET 'cdn.technologyreview.com', NoQuery

    # Twitch
    GET 'www.twitch.tv', Desktop
    if ENV.has_key? 'TWITCH'
      %w(api.twitch.tv
         gql.twitch.tv
         www.twitch.tv
).map{|h|Allow h}
    end

    # Twitter
    Allow 'api.twitter.com'
    Allow 'proxsee.pscp.tv'

    GotoTwitter = -> r {[301,{'Location' => 'https://twitter.com' + r.path },[]]}
    GET 'mobile.twitter.com', GotoTwitter
    GET 'tweettunnel.com', GotoTwitter
    GET 'www.twitter.com', GotoTwitter

    GET 't.co', -> r {r.parts[0] == 'i' ? r.deny : r.fetch}

    GET 'twitter.com', -> r {
      r.desktopUA
      if !r.path || r.path == '/'
        r.env[:links][:feed] = '/feed'
        RootIndex[r]
      elsif r.path == '/feed'
        'com/twitter/*/.follow*'.R.glob.map(&:dir).map(&:basename).shuffle.each_slice(18){|s|
          '/search'.R(r.env).fetch intermediate: true,
                                   noRDF: true,
                                   query: {vertical: :default, f: :tweets, q: s.map{|u|'from:'+u}.join('+OR+')}}
        r.chrono_sort
        r.indexRDF.graphResponse
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
    GET 'player.vimeo.com', Desktop
    GET 'vimeo.com', Desktop

    # WaPo
    GET 'www.washingtonpost.com', -> r {(r.parts[0]=='resizer' ? Resizer : NoGunk)[r]}

    #WCVB
    GET 'www.wcvb.com', Desktop

    # WGBH
    GET 'wgbh.brightspotcdn.com', GoIfURL

    # Wiley
    Cookies 'agupubs.onlinelibrary.wiley.com'

    # Wix
    GET 'static.parastorage.com', NoGunk
    GET 'static.wixstatic.com', NoGunk

    # WordPress
    #Allow 'public-api.wordpress.com'
    %w(
public-api.wordpress.com
videos.files.wordpress.com
).map{|host|
      GET host, Fetch}

    (0..7).map{|i| GET "i#{i}.wp.com", NoQuery}

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
    Allow 'youtubei.googleapis.com'
    Allow 'www.youtube.com'
    GotoYoutube = -> r {[301, {'Location' => 'https://www.youtube.com' + r.env['REQUEST_URI']}, []]}
    GET 's.ytimg.com', Desktop
    GET 'youtube.com', GotoYoutube
    GET 'm.youtube.com', GotoYoutube
    GET 'www.youtube.com', -> r {
      fn = r.parts[0]
      if %w{attribution_link redirect}.member? fn
        [301, {'Location' =>  r.env[:query]['q'] || r.env[:query]['u']},[]]
      elsif !r.gunkURI && (!fn || %w(browse_ajax c channel embed feed get_video_info guide_ajax
heartbeat iframe_api live_chat manifest.json opensearch playlist results signin user watch watch_videos yts).member?(fn))
        Desktop[r]
      elsif r.env[:query]['allow'] == ServerKey
        r.fetch
      else
        r.deny
      end}
    GET 'www.invidio.us', GotoYoutube

    POST 'www.youtube.com', -> r {
      if r.parts.member? 'stats'
        r.denyPOST
      elsif r.env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/i
        r.POSTthru
      else
        r.denyPOST
      end}

    GET 'youtu.be', -> r {[301, {'Location' => 'https://www.youtube.com/watch?v=' + r.path[1..-1]}, []]}

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
        yield subject, Content, Webize::HTML.clean(content.inner_html)}
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
  def Instagram doc
    doc.css('script').map{|script|
      if script.inner_text.match? IGgraph
        graph = ::JSON.parse script.inner_text.sub(IGgraph,'')[0..-2]
        Webize::HTML.webizeHash(graph){|h|
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
    yield subject, Content, (Webize::HTML.clean tree['data']['html'])
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
          yield s, Content, Webize::HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
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
