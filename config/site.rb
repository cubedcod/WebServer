module Webize
  module HTML
    class Reader

      SiteGunk = {'www.google.com' => %w(div.logo h1 h2),
                  'www.bostonmagazine.com' => %w(a[href*='scrapertrap'])}

      Triplr = {
        'apnews.com' => :AP,
        'lwn.net' => :LWN,
        'news.ycombinator.com' => :HackerNews,
        'twitter.com' => :Twitter,
        'www.aliexpress.com' => :AX,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.google.com' => :GoogleHTML,
        'www.instagram.com' => :Instagram,
        'www.patriotledger.com' => :GateHouse,
        'www.providencejournal.com' => :GateHouse,
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

    Gunk = %r([-.:_\/?&=~]
((block|page)?a(d(vert(i[sz](ement|ing))?)?|ffiliate|nalytic)s?(bl(oc)?k(er|ing)?.*|id|slots?|tools?|types?|units?|words?)?|appnexus|(app)?
b(anner|eacon|reakingnew)s?|
c(ampaign|edexis|hartbeat.*|loudflare|ollector|omscore|onversion|ookie(c(hoice|onsent)|law|notice)?s?|se)|
de(als|tect)|
e(moji.*\.js|ndscreen|nsighten|scenic|vidon)|
facebook|(web)?fonts?|
g(dpr|eo(ip|locate)|igya|pt|tag|tm)|.*
(header|pre)[-_]?bid.*|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|
kr(ux|xd).*|
log(event|g(er|ing))?|(app|s)?
m(e(asurement|t(er|rics?))|ms|tr)|
new(relic|sletter)|
o(m(niture|tr)|nboarding|ptanon|utbrain)|
p(a(idpost|rtner|ywall)|er(imeter-?x|sonaliz(ation|e))|i(wik|xel(propagate)?)|lacement|op(over|up)|repopulator|romo(tion)?s?|ubmatic|[vx])|
quantcast|
record(event|stats?)|re?t(ar)?ge?t(ing)?|remote[-_]?(control)?|rpc|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|ervice[-_]?worker|i(ftscience|gnalr|tenotice)|o(cial(shar(e|ing))?|urcepoint)|ponsor(ed)?|so|tat(istic)?s?|ubscriber|w.js|yn(c|dicat(ed|ion)))|
t(aboola|(arget|rack)(ers?|ing)|ampering|bproxy|ea(lium|ser)|elemetry|hirdparty|inypass|racing|rend(ing|s)|ypeface)|autotrack|
u(rchin|serlocation|tm)|
viral|
wp-rum)
([-.:_\/?&=~]|$)|
\.gif\?)xi

    SiteDir  = (Pathname.new __dir__).relative_path_from Pathname.new Dir.pwd
    SiteGIF = SiteDir.join('site.gif').read
    SiteCSS = SiteDir.join('site.css').read + SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
  end
  module HTTP
    Desktop = -> r {r.desktopUI.fetch}
    DesktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
    GoIfURL = -> r {r.env[:query].has_key?('url') ? GotoURL[r] : r.deny}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.env[:query]['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.env[:query]['url']||r.env[:query]['q'])}, []]}
    Icon    = -> r {r.env[:deny] = true; [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}
    NoJS    = -> r {(r.gunkURI || r.ext=='js') ? r.deny : r.fetch}
    NoQuery = -> r {r.qs.empty? ? r.fetch : [301, {'Location' => r.env['REQUEST_PATH']}, []]}
    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/(filter[^\/]+\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1] + '?allow='+ServerKey}, []] : NoJS[r]
      else
        NoJS[r]
      end}

    # ABC
    Allow 'abcnews.go.com'

    # Amazon
    AmazonMedia = -> r {%w(css jpg mp4 png webm webp).member?(r.ext.downcase) && r.env['HTTP_REFERER']&.match(/amazon\.com/) && r.fetch || r.deny}
    if ENV.has_key? 'AMAZON'
      %w(            amazon.com
images-na.ssl-images-amazon.com
                 www.amazon.com).map{|h|Allow h}
    else
      GET 'amazon.com', NoJS
      GET 'www.amazon.com', NoJS
      GET 'images-na.ssl-images-amazon.com', AmazonMedia
      GET 'm.media-amazon.com', AmazonMedia
    end

    # Boston Globe
    GET 'bos.gl', -> r {r.fetch scheme: :http}
    GET 'bostonglobe-prod.cdn.arcpublishing.com', Resizer

    # Brightcove
    Allow 'players.brightcove.net'
    Allow 'edge.api.brightcove.com'

    # Brightspot
    GET 'ca-times.brightspotcdn.com', GoIfURL

    # BusinessWire
    GET 'cts.businesswire.com', GoIfURL

    # CircleCI
    GET 'circleci.com', -> r {r.parts[0] == 'blog' ? r.fetch : r.deny}

    # Cloudflare
    Allow 'cdnjs.cloudflare.com'

    # Costco
    Allow 'www.costco.com'

    # CNN
    %w(cdn www).map{|host|
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

    # Facebook
    FBgunk = %w(common connect pages_reaction_units plugins security tr)
    FBlite = -> r {FBgunk.member?(r.parts[0]) ? r.deny : r.fetch}
    %w(  facebook.com
business.facebook.com
       m.facebook.com
     www.facebook.com
    www.instagram.com).map{|host|
      if ENV.has_key?('FACEBOOK')
        Allow host
      else
        GET host, FBlite unless host.match /insta/
      end}
    %w(l.instagram.com
       l.facebook.com
      lm.facebook.com
).map{|host|
      GET host, GotoU}
    GET 'www.pictame.com', -> r {r.parts[1] ? [301, {'Location' => 'https://www.instagram.com/'+r.parts[1]}, []] : r.deny}

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    # Google
    GoogleSearch = -> r {
      case r.path
      when '/'
        r.fetch
      when /^.maps/
        Desktop[r]
      when '/search'
        if r.env[:query]['q']&.match? /^(https?:\/\/|l(:8000|\/)|localhost|view-source)/
          [301, {'Location' => r.env[:query]['q'].sub(/^l/,'http://l')}, []]
        else
          r.fetch
        end
      when '/url'
        GotoURL[r]
      else
        r.deny
      end}

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
    storage.googleapis.com
).map{|h| Allow h }

    if ENV.has_key? 'GOOGLE'
    %w(accounts.google.com
android.clients.google.com
           apis.google.com
         chrome.google.com
       clients1.google.com
       clients4.google.com
       clients5.google.com
      feedproxy.google.com
      feeds.feedburner.com
                google.com
             id.google.com
             kh.google.com
           mail.google.com
           play.google.com
       play.googleapis.com
           ssl.gstatic.com
 suggestqueries.google.com
            www.google.com
        www.googleapis.com
           www.gstatic.com
         www.recaptcha.net
).map{|host|
      Allow host}
    else
      GET     'google.com', GoogleSearch
      GET 'www.google.com', GoogleSearch
    end

    # Imgur
    GET 'i.imgur.com', Desktop

    # Inrupt
    Allow 'dev.inrupt.net'

    # Instagram
    GET 'www.instagram.com', -> r {r.path=='/' ? r.cachedGraph : r.fetch}

    # Linkedin
    if ENV.has_key? 'LINKEDIN'
      Allow 'media.licdn.com'
      Allow 'www.linkedin.com'
    else
      GET 'media.licdn.com', NoJS
      GET 'www.linkedin.com', NoJS
    end

    # Medium
    GET 'medium.com', -> r {r.env[:query].has_key?('redirecturl') ? [301, {'Location' => r.env[:query]['redirecturl']}, []] : r.fetch}

    # Meetup
    GET 'www.meetup.com', -> r {r.fetch}

    # Meredith
    GET 'imagesvc.meredithcorp.io', GoIfURL

    # Mixcloud
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
      Allow host}

    # Outline
    GET 'outline.com', -> r {
      if r.parts[0] == 'favicon.ico'
        r.deny
      else
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['SERVER_NAME'] = 'outlineapi.com'
        options = {intermediate: true}
        (if r.parts.size == 1
          options[:query] = {id: r.parts[0]}
          '/v4/get_article'.R(r.env).fetch optionss
        elsif r.env['REQUEST_PATH'][1..5] == 'https'
          options[:query] = {source_url: r.env['REQUEST_PATH'][1..-1]}
          '/article'.R(r.env).fetch options
         end).index.graphResponse
      end}

    # Reddit
    Allow 'reddit-uploaded-media.s3-accelerate.amazonaws.com'
    %w(oauth www).map{|host| Allow host + '.reddit.com'}                      # required to post
    %w(gateway gql s).map{|host| Allow host + '.reddit.com'} if ENV['REDDIT'] # messaging / notification / JSON-API hosts
    GET 'old.reddit.com', -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path}, []]}
    GET 'reddit.com',     -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path}, []]}
    GET 'www.reddit.com', -> r {
      options = {}
      r = ('/r/' + r.subscriptions.join('+') + '/new').R r.env if r.path == '/'
      r.desktopUI if r.desktopUA? || r.parts.member?('submit')
      options[:suffix] = '.rss' if r.ext.empty? && !r.upstreamUI?
      depth = r.parts.size
      r.env[:links][:up] = if [3,6].member? depth
                             r.dirname
                           elsif 5 == depth
                             '/' + r.parts[0..1].join('/')
                           else
                             '/'
                           end
      r.fetch options}

    # Redfin
    GET 'www.redfin.com', Desktop

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
    GET 'cdn.shopify.com', NoJS

    # Skimmer
    GET 'go.skimresources.com', GotoURL

    # Soundcloud
    GET 'gate.sc', GotoURL
    GET 'soundcloud.com', Desktop
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
    GET 'soundcloud.com', -> r { r.desktopUI.get }

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
    GET 'www.twitter.com', GotoTwitter
    GET 't.co', -> r {r.parts[0] == 'i' ? r.deny : r.fetch}
    GET 'twitter.com', -> r {
      r.desktopUA
      if !r.path || r.path == '/'
        '//twitter.com'.R.subscriptions.shuffle.each_slice(18){|s|
          '/search'.R(r.env).fetch intermediate: true, noRDF: true, query: {vertical: :default, f: :tweets, q: s.map{|u|'from:'+u}.join('+OR+')}}
        r.index.graphResponse
      elsif r.gunkURI
        r.deny
      else
        r.env[:links][:up] = '/' + r.parts[0] if r.path.match? /\/status\/\d+\/?$/
        r.env[:links][:up] = '/' if r.parts.size == 1
        r.fetch noRDF: true
      end}

    GET 'redirect.viglink.com', GotoU

    # WGBH
    GET 'wgbh.brightspotcdn.com', GoIfURL

    # WordPress
    (0..7).map{|i|
      GET "i#{i}.wp.com", NoQuery}

    # Yahoo!
    Allow 'news.yahoo.com'
    GET 's.yimg.com', -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.fetch
      end}

    # Yelp
    GET 'www.yelp.com', -> r {r.env[:query]['redirect_url'] ? [301, {'Location' => r.env[:query]['redirect_url']},[]] : r.fetch}

    # YouTube
    Allow 'www.youtube.com'
    GET 's.ytimg.com', Desktop
    GET 'youtube.com',   -> r {[301, {'Location' => 'https://www.youtube.com' + r.env['REQUEST_URI']}, []]}
    GET 'm.youtube.com', -> r {[301, {'Location' => 'https://www.youtube.com' + r.env['REQUEST_URI']}, []]}
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

    POST 'www.youtube.com', -> r {
      if r.parts.member? 'stats'
        r.denyPOST
      elsif r.env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/i
        r.POSTthru
      else
        r.denyPOST
      end}

    GET 'youtu.be', -> r {[301, {'Location' => 'https://www.youtube.com/watch?v=' + r.path[1..-1]}, []]}

    # Zillow
    Allow 'www.zillow.com'
    GET 'www.zillow.com', Desktop

  end

  def subscriptions
    (case host
     when /reddit.com$/
       '/www.reddit.com/r/*/.sub'
     when /twitter.com$/
       '/twitter.com/*/.following'
     else
       '/feed/'+[host, *parts].join('.')
     end).R.glob.map(&:dir).map(&:basename)
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
    %w{#fixed_sidebar}.map{|s|doc.css(s).map &:remove}
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
        s = 'https://twitter.com' + (tweet.css('.js-permalink').attr('href') || tweet.attr('data-permalink-path'))
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

  def YouTube doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
