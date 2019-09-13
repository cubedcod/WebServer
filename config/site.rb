module Webize
  module HTML
    class Reader

      Gunk = %w( .ActionBar .SocialBar )

      SiteGunk = {'www.google.com' => %w(div.logo h1 h2),
                  'www.bostonmagazine.com' => %w(a[href*='scrapertrap'])}
      # HTML to RDF method map
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
    # JSON to RDF method map
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
    ConfDir  = (Pathname.new __dir__).relative_path_from Pathname.new Dir.pwd

    Extensions = RDF::Format.file_extensions.invert

    FeedURL = {}
    'feeds/*.u'.R.glob.map{|list|(open list.relPath).readlines.map(&:chomp).map{|u| FeedURL[u] = u.R }}

    CDN = /amazon|azure|cloud(flare|front|inary)|digitalocean|fa(cebook|stly)|heroku|netdna|ra(ckcdn|wgit)|stackpath|usercontent/
    CDNsubdomain = /(s3.+amazonaws|storage\.googleapis)\.com$/

    GunkURI = %r([-.:_\/?&=~]((block|page)?
a(d(vert(i[sz](ement|ing))?)?|ffiliate|nalytic)s?(bl(oc)?k(er|ing)?.*|id|slot|type|words?)?|(app)?
b(anner|eacon|reakingnew)s?|
c(ampaign|edexis|hartbeat.*|ollector|omscore|onversion|ookie(c(hoice|onsent)|law|notice)?s?|se)|
detect|
e(moji.*\.js|nsighten|scenic|vidon)|(web)?
fonts?|
g(dpr|eo(ip|locate)|igya|pt|tag|tm|uid)|.*
(header|pre)[-_]?bid.*|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|
kr(ux|xd).*|
log(event|g(er|ing))?|(app|s)?
m(e(asurement|ssaging|t(er|rics?))|ms|tr)|
new(relic|sletter)|
o(m(niture|tr)|nboarding|ptanon|utbrain)|
p(a(idpost|y(ments?|wall))|er(imeter-?x|sonaliz(ation|e))|i(wik|xel(propagate)?)|lacement|op(over|up)|romo(tion)?s?|ubmatic|[vx])|
quantcast|
reco(mmend(ation)?s?|rd(event|stats?)?)|re?t(ar)?ge?t(ing)?|rpc|
s?s(a(fe[-_]?browsing|ilthru)|ervice[-_]?worker|i(ftscience|gnalr|tenotice)|o(cial|urcepoint)|ponsored|so|tat(istic)?s?|ubscri(ber?|ption)|w.js|ync)|
t(aboola|(arget|rack)(ers?|ing)?|bproxy|ea(lium|ser)|inypass|rend(ing|s))|autotrack|
u(rchin|serlocation|tm)|
viral|
wp-rum)([-.:_\/?&=~]|$)|
\.((gif|png)\?|otf|ttf|woff2?)|\/[a-z]\?)xi

    ServerAddr = 'http://localhost:8000'

    SiteFont = ConfDir.join('fonts/hack-regular-subset.woff2').read
    SiteGIF = ConfDir.join('site.gif').read
    SiteCSS = ConfDir.join('site.css').read + ConfDir.join('code.css').read
    SiteJS  = ConfDir.join('site.js').read
  end
  module HTML
    Avatars = {}
    'avatars/*png'.R.glob.map{|a|
      uri = Base64.decode64(a.basename.split('.')[0]).downcase
      location = ServerAddr + a.path
      #puts "Avatar: #{uri} -> #{location}"
      Avatars[uri] = location}
  end
  module HTTP

    DesktopUA = ['Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3903.0 Safari/537.36',
                 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3906.0 Safari/537.36',
                 'Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0']

    # path handlers

    GET '/mail', -> r {
      if r.local?
        if r.path == '/mail' # inbox redirect
          [302, {'Location' => '/d/*/msg*?head&sort=date&view=table'}, []]
        else
          r.local
        end
      else
        r.fetch
      end}

    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.env[:query]['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.env[:query]['url']||r.env[:query]['q'])}, []]}
    GoIfURL = -> r {r.env[:query].has_key?('url') ? GotoURL[r] : r.noexec}
    Icon    = -> r {r.env[:deny] = true; [200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}
    Lite    = -> r {r.gunkURI? ? r.deny : r.noexec}
    NoQuery = -> r {r.qs.empty? ? r.noexec : [301, {'Location' => r.env['REQUEST_PATH']}, []]}

    GET '/favicon.ico', Icon

    GET '/resizer', -> r {
      parts = r.path.split /\/\d+x\d+\/(filter[^\/]+\/)?/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.fetch
      end}

    GET '/storyimage', -> r {
      parts = r.path.split '&'
      if parts.size > 1
        [301, {'Location' => 'https://' + r.host + parts[0]}, []]
      else
        r.fetch
      end}

    GET '/thumbnail', GoIfURL

    GET '/clicks/track', GotoURL
    GET '/url', GotoURL

    # site handlers

    # Air
    AllowHost 'events.air.tv'
    AllowHost 'event-listener.air.tv'

    # Alibaba
    %w(www.aliexpress.com ae-cn.alicdn.com ae01.alicdn.com i.alicdn.com).map{|h|AllowHost h}

    # Amazon
    AmazonMedia = -> r {%w(css jpg mp4 png webm webp).member?(r.ext.downcase) && r.env['HTTP_REFERER']&.match(/amazon\.com/) && r.noexec || r.deny}
    if ENV.has_key? 'AMAZON'
      %w(            amazon.com
images-na.ssl-images-amazon.com
                 www.amazon.com).map{|h|AllowHost h}
    else
      GET 'amazon.com', Lite
      GET 'www.amazon.com', Lite
      GET 'images-na.ssl-images-amazon.com', AmazonMedia
      GET 'm.media-amazon.com', AmazonMedia
    end

    # AmericanInno
    AllowCookies 'www.americaninno.com'

    # AOL
    GET 'o.aolcdn.com', -> r {r.env[:query].has_key?('image_uri') ? [301, {'Location' => r.env[:query]['image_uri']}, []] : r.noexec}

    # Bizjournals
    AllowCookies 'www.bizjournals.com'

    # Bloomberg
    AllowCookies 'www.bloomberg.com'

    # Boston Globe
    GET 'bos.gl', -> r {r.fetch scheme: :http}

    # Brave
    AllowHost 'brave.com' if ENV.has_key? 'BRAVE'

    # Brightcove
    AllowHost 'players.brightcove.net'
    AllowHost 'edge.api.brightcove.com'

    # Brightspot
    GET 'ca-times.brightspotcdn.com', GoIfURL

    # BusinessWire
    GET 'cts.businesswire.com', GoIfURL

    # BuzzFeed
    AllowHost 'img.buzzfeed.com'
    AllowHost 'www.buzzfeed.com'

    # Cloudflare
    AllowHost 'cdnjs.cloudflare.com'

    # CNN
    GET 'dynaimage.cdn.cnn.com', GotoBasename

    # DartSearch
    GET 'clickserve.dartsearch.net', -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # Disney
    AllowHost 'abcnews.go.com'

    # DuckDuckGo
    GET 'duckduckgo.com', -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.fetch}
    GET 'proxy.duckduckgo.com', -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.fetch}

    # eBay
    AllowHost 'ebay.com'
    AllowHost 'www.ebay.com'
    AllowHost 'ir.ebaystatic.com'
    GET 'i.ebayimg.com', -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.noexec
      end}
    GET 'rover.ebay.com', -> r {
      r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # Economist
    AllowHost 'www.economist.com'

    # Eventbrite
    #GET 'img.evbuc.com', GotoBasename

    # Facebook
    FBgunk = %w(common connect pages_reaction_units plugins security tr)
    FBlite = -> r {ENV.has_key?('FACEBOOK') ? r.fetch : FBgunk.member?(r.parts[0]) ? r.deny : r.noexec}
    %w(facebook.com business.facebook.com www.facebook.com).map{|host|GET host, FBlite}
    %w(l.instagram.com l.facebook.com).map{|host| GET host, GotoU}

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    #FSDN
    GET 'a.fsdn.com', -> r {r.noexec}

    # Gitter
    GET 'gitter.im', -> req {req.desktop.fetch}

    # Google
    GoogleLite = -> r {
      case r.path
      when '/'
        r.noexec
      when '/search'
        if r.env[:query]['q']&.match? /^(https?:\/\/|l:8000|localhost)/
          [301, {'Location' => r.env[:query]['q'].sub(/^l/,'http://l')}, []]
        else
          r.noexec
        end
      when /^\/maps/
        r.desktop.fetch
      else
        r.deny
      end}

    %w(ajax.googleapis.com
encrypted-tbn0.gstatic.com
encrypted-tbn1.gstatic.com
encrypted-tbn2.gstatic.com
encrypted-tbn3.gstatic.com
         groups.google.com
             kh.google.com
           maps.google.com
       maps.googleapis.com
          maps.gstatic.com
).map{|h| AllowHost h }

    if ENV.has_key? 'GOOGLE'
    %w(accounts.google.com
android.clients.google.com
           apis.google.com
          books.google.com
         chrome.google.com
       clients1.google.com
       clients4.google.com
       clients5.google.com
     developers.google.com
          drive.google.com
      feedproxy.google.com
      feeds.feedburner.com
                google.com
         images.google.com
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
      AllowHost host}
    else
      AllowCookies 'www.google.com'
      AllowRefer   'www.google.com'
      GET     'google.com', GoogleLite
      GET 'www.google.com', GoogleLite
    end
    GET 'www.googleadservices.com', -> r {r.env[:query]['adurl'] ? [301, {'Location' => r.env[:query]['adurl']},[]] : r.deny}

    # Grabien
    AllowHost 'news.grabien.com'

    # Linkedin
    if ENV.has_key? 'LINKEDIN'
      AllowHost 'www.linkedin.com'
      AllowHost 'media.licdn.com'
    end

    # Medium
    GET 'medium.com', -> r {r.env[:query].has_key?('redirecturl') ? [301, {'Location' => r.env[:query]['redirecturl']}, []] : r.noexec}

    # Meredith
    GET 'imagesvc.meredithcorp.io', GoIfURL

    # Microsoft
    GET 'www.bing.com', -> r {
      (%w(fd hamburger Identity notifications secure).member?(r.parts[0]) || r.path.index('/api/ping') == 0) ? r.deny : r.fetch}
    AllowHost 'www.msn.com'

    # Mozilla
    %w( addons.mozilla.org
addons-amo.cdn.mozilla.net
    addons.cdn.mozilla.net
         hacks.mozilla.org
).map{|h| AllowHost h } if ENV.has_key? 'MOZILLA'

    GET 'detectportal.firefox.com', -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # NYTimes
    %w(cooking.nytimes.com
           www.nytimes.com).map{|host|
      AllowHost host}

    # Outline
    GET 'outline.com', -> r {
      if r.parts[0] == 'favicon.ico'
        r.deny
      else
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['SERVER_NAME'] = 'outlineapi.com'
        r.env[:intermediate] = true
        (if r.parts.size == 1
          r.env[:query] = {id: r.parts[0]}
          '/v4/get_article'.R(r.env).fetch
        elsif r.env['REQUEST_PATH'][1..5] == 'https'
          r.env[:query] = {source_url: r.env['REQUEST_PATH'][1..-1]}
          '/article'.R(r.env).fetch
         end).index.graphResponse
      end}

    # Reddit
    AllowHost 'oauth.reddit.com'
    AllowHost 'reddit-uploaded-media.s3-accelerate.amazonaws.com'
    AllowHost 'www.reddit.com'
    GotoReddit = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    GET 'reddit.com', GotoReddit
    GET 'old.reddit.com', GotoReddit
    GET 'www.reddit.com', -> r {
      options = {}
      if r.parts.member?('submit') || r.upstreamFormat?
        r.desktop
      else
        r.env[:transform] = true
        r.env[:query]['sort'] ||= 'date'
        r.env[:query]['view'] ||= 'table'
        options[:suffix] = '.rss' if r.ext.empty?
      end
      if r.path == '/'
        ('/r/'+r.subscriptions.join('+')+'/new').R(r.env).fetch options
      elsif r.gunkURI?
        r.deny
      else
        depth = r.parts.size
        r.env[:links][:up] = if [3,6].member? depth
                               r.dirname
                             elsif 5 == depth
                               '/' + r.parts[0..1].join('/')
                             else
                               '/'
                             end
        r.fetch options
      end}

    # Redfin
    AllowCookies 'www.redfin.com'

    # Reuters
    (0..5).map{|i|
      GET "s#{i}.reutersmedia.net", -> r {
        if r.env[:query].has_key? 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + HTTP.qs(r.env[:query].reject{|k,_|k=='w'})}, []]
        else
          r.noexec
        end}}

    # Shopify
    GET 'cdn.shopify.com', -> r {r.qs.empty? ? r.noexec : [301, {'Location' => r.path}, []]}

    # Skimmer
    GET 'go.skimresources.com', GotoURL

    # Soundcloud
    GET 'gate.sc', GotoURL

    %w(api-v2.soundcloud.com
   api-widget.soundcloud.com
              soundcloud.com
            w.soundcloud.com
).map{|h|AllowHost h}

    # Static9
    GET 'imageresizer.static9.net.au', GotoBasename

    # Twitter
    AllowHost 'api.twitter.com'
    GotoTwitter = -> r {[301,{'Location' => 'https://twitter.com' + r.path },[]]}
    GET 'mobile.twitter.com', GotoTwitter
    GET 'www.twitter.com', GotoTwitter
    GET 't.co', -> r {r.parts[0] == 'i' ? r.deny : r.noexec}
    GET 'twitter.com', -> r {
      if !r.path || r.path == '/'
        r.env[:intermediate] = true # defer indexing
        r.env[:no_RDFa] = true # skip embedded-RDF search
        '//twitter.com'.R.subscriptions.shuffle.each_slice(18){|s|
          r.env[:query] = { vertical: :default, f: :tweets, q: s.map{|u|'from:' + u}.join('+OR+')}
          '//twitter.com/search'.R(r.env).fetch}
        r.env[:query] = {'sort' => 'date', 'view' => 'table'} # chronological sort
        r.index.graphResponse
      elsif r.gunkURI?
        r.deny
      else
        r.env[:links][:up] = '/' + r.parts[0] + '?view=table&sort=date' if r.path.match? /\/status\/\d+\/?$/
        r.env[:links][:up] = '/' if r.parts.size == 1
        r.fetch
      end}

    # WGBH
    GET 'wgbh.brightspotcdn.com', GoIfURL

    # WordPress
    (0..7).map{|i| GET "i#{i}.wp.com", NoQuery}

    # Yahoo!
    AllowHost 'news.yahoo.com'
    GET 's.yimg.com', -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.noexec
      end}

    # Yelp
    GET 'www.yelp.com', -> r {r.env[:query]['redirect_url'] ? [301, {'Location' => r.env[:query]['redirect_url']},[]] : r.noexec}

    # YouTube
    GET 's.ytimg.com', -> r {r.desktop.fetch}
    GET 'youtube.com', -> r {[301, {'Location' => 'https://www.youtube.com' + r.env['REQUEST_URI']}, []]}
    GET 'm.youtube.com', -> r {[301, {'Location' => 'https://www.youtube.com' + r.env['REQUEST_URI']}, []]}
    GET 'www.youtube.com', -> r {
      mode = r.parts[0]
      if %w{attribution_link redirect}.member? mode
        [301, {'Location' =>  r.env[:query]['q'] || r.env[:query]['u']},[]]
      elsif !mode || %w(browse_ajax c channel embed feed get_video_info
guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist
results signin user watch watch_videos yts).member?(mode)
        r.desktop.fetch
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
    AllowHost 'www.zillow.com'
    #AllowCookies 'www.zillow.com'

    def subscriptionFile slug=nil
      (case host
       when /reddit.com$/
         '/www.reddit.com/r/' + (slug || parts[1] || '') + '/.sub'
       when /^twitter.com$/
         '/twitter.com/' + (slug || parts[0] || '') + '/.following'
       else
         '/feed/' + [host, *parts].join('.')
       end).R
    end

  end

  def HTTP.twits
    `cd ~/src/WebServer && git show -s --format=%B a3e600d66f2fd850577f70445a0b3b8b53b81e89`.split.map{|twit|
      ('https://twitter.com/' + twit).R.subscribe}
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
      user = post.css('.hnuser')[0]
      yield subject, Creator, (base + user['href']).R
      yield subject, Creator, user.inner_text
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
