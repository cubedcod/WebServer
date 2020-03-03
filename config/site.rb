# coding: utf-8
module Webize
  module HTML
    class Reader
      Triplr = {
        'apnews.com' => :AP,
        'boards.4chan.org' => :FourChan,
        'boards.4channel.org' => :FourChan,
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
    CacheFormats = %w(css geojson gif html ico jpeg jpg js json m3u8 m4a md mp3 mp4 opus pdf png svg ts webm webp xml) # cached filetypes
    CDNhost = /\.(akamai(hd)?|amazonaws|.*cdn|cloud(f(lare|ront)|inary)|fastly|googleapis|netdna.*)\.(com|io|net)$/
    CookieHost = /\.(akamai(hd)?|bandcamp|ttvnw)\.(com|net)$/
    GunkHosts = {}
    POSThost = /^video.*.ttvnw.net$/
    UIhosts = %w(players.brightcove.net www.redditmedia.com)
    StaticFormats = CacheFormats - %w(json html xml)
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd
    SiteDir.join('gunk_hosts').each_line{|l|
      cursor = GunkHosts
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|cursor = cursor[name] ||= {}}}
    FeedIcon = SiteDir.join('feed.svg').read
    SiteFont = SiteDir.join('fonts/hack-regular-subset.woff2').read
    SiteGIF = SiteDir.join('site.gif').read
    SiteCSS = SiteDir.join('site.css').read
    CodeCSS = SiteDir.join('code.css').read
    SiteJS  = SiteDir.join('site.js').read
  end
  module HTTP
    DesktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/888.38 (KHTML, like Gecko) Chrome/80.0.3888.80 Safari/888.38'
    MobileUA = 'Mozilla/5.0 (Linux; Android 9; SM-G960F Build/PPR1.180610.011; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/74.0.3729.157 Mobile Safari/537.36'

    # common handlers
    Fetch = -> r {r.fetch}
    GoIfURL = -> r {r.query_values&.has_key?('url') ? GotoURL[r] : NoGunk[r]}
    GotoBasename = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}
    GotoU   = -> r {[301, {'Location' =>  r.query_values['u']}, []]}
    GotoURL = -> r {[301, {'Location' => (r.query_values['url']||r.query_values['q'])}, []]}
    NoGunk  = -> r {r.gunkURI && (r.query_values || {})['allow'] != ServerKey && r.deny || r.fetch}

    NoQuery = -> r {
      if !r.query                         # request without query
        NoGunk[r].yield_self{|s,h,b|      #  inspect response
          h.keys.map{|k|                  #  strip query from new location
            h[k] = h[k].split('?')[0] if k.downcase == 'location' && h[k].match?(/\?/)}
          [s,h,b]}                        #  response
      else                                # request with query
        [302, {'Location' => r.path}, []] #  redirect to path
      end}

    RootIndex = -> r {
      if r.path == '/' || r.path.match?(GlobChars)
        r.nodeResponse
      else
        r.chrono_sort if r.parts.size == 1
        NoGunk[r]
      end}

    Resizer = -> r {
      if r.parts[0] == 'resizer'
        parts = r.path.split /\/\d+x\d+\/((filter|smart)[^\/]*\/)?/
        parts.size > 1 ? [302, {'Location' => 'https://' + parts[-1]}, []] : NoGunk[r]
      else
        NoGunk[r]
      end}

    # URL shorteners / redirectors
    %w(bit.ly bos.gl w.bos.gl
 cbsn.ws dlvr.it econ.trib.al
 feedproxy.google.com feeds.feedburner.com feeds.reuters.com
 hubs.ly
 reut.rs rss.cnn.com rssfeeds.usatoday.com
 t.co ti.me tinyurl.com trib.al wired.trib.al).map{|short| GET short, NoQuery }

    # Adobe
    Allow 'entitlement.auth.adobe.com'
    Allow 'sp.auth.adobe.com'

    # Amazon
    AmazonHost = -> r {(%w(www.amazon.com www.audible.com www.imdb.com).member?(r.env[:refhost]) || (r.query_values||{})['allow'] == ServerKey) ? NoGunk[r] : r.deny}
    %w(amazon.com www.amazon.com).map{|host| GET host}
    GET 'images-na.ssl-images-amazon.com', AmazonHost
    GET 'm.media-amazon.com', AmazonHost

    # Anvato
    Allow 'tkx.apis.anvato.net'

    # Boston Globe
    GET 'bostonglobe-prod.cdn.arcpublishing.com', Resizer

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

    # Cloudflare
    GET 'cdnjs.cloudflare.com'

    # CNN
    GET 'dynaimage.cdn.cnn.com', GotoBasename

    # DartSearch
    GET 'clickserve.dartsearch.net', -> r {[301,{'Location' => r.query_values['ds_dest_url']}, []]}

    # Disqus
    GET 'c.disquscdn.com', GoIfURL
    GET 'disq.us', GoIfURL

    # DuckDuckGo
    GET 'proxy.duckduckgo.com', -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.query_values['u']}, []] : r.fetch}

    # eBay
    Allow 'www.ebay.com'
    %w(ebay.com
   www.ebay.com
    ir.ebaystatic.com
thumbs.ebaystatic.com).map{|host| GET host }

    GET 'i.ebayimg.com', -> r {r.basename.match?(/s-l(64|96|200|225).jpg/) ? [301, {'Location' => File.dirname(r.path) + '/s-l1600.jpg'}, []] : r.fetch}
    GET 'rover.ebay.com', -> r {(r.query_values||{}).has_key?('mpre') ? [301, {'Location' => r.query_values['mpre']}, []] : r.deny}

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

    # Forbes
    GET 'thumbor.forbes.com', -> r {[301, {'Location' => Rack::Utils.unescape(r.parts[-1])}, []]}

    # Gfycat
    GET 'gfycat.com'
    GET 'thumbs.gfycat.com'

    # Google
    GET 'ajax.googleapis.com'  # Javascript libraries
    GET 'google.com', -> r {[301, {'Location' => 'https://www.google.com' + r.env['REQUEST_URI'] }, []]}
    GET 'www.google.com', -> r {
      case r.path
      when /^.(images|maps|search)/
        r.fetch
      when '/url'
        GotoURL[r]
      else
        r.deny
      end}

    # Guardian
    GET 'i.guim.co.uk'
    GET 'assets.guim.co.uk'
    GET 'www.theguardian.com'

    # Instagram
    Cookies 'www.instagram.com'
    GET 'instagram.com', -> r {[301, {'Location' => 'https://www.instagram.com' + r.path}, []]}
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

    # JWPlayer
    GET 'ssl.p.jwpcdn.com'

    # MassLive
    GET 'i.masslive.com', Resizer

    # Meredith
    GET 'imagesvc.meredithcorp.io', GoIfURL

    # NYTimes
    %w(cooking www).map{|host|GET host+'.nytimes.com'}

    # Reddit
    GET 'reddit.com', -> r {[301, {'Location' => 'https://www.reddit.com/r/Rad_Decentralization+SOLID+StallmanWasRight+dancehall+darknetplan+fossdroid+selfhosted+shortwave/new/'}, []]}
    GET 'www.reddit.com', -> r { parts = r.parts
      r.chrono_sort if parts[-1] == 'new' || parts.size == 5                    # chrono sort
      options = {suffix: '.rss'} if r.ext.empty? && !r.upstreamUI?              # MIME preference
      r.env[:links][:prev] = ['https://old.reddit.com',r.path,'?',r.query].join # pagination link
      r.fetch options}

    GET 'old.reddit.com', -> r {
      r.upstreamUI.env['HTTP_USER_AGENT'] = DesktopUA
      r.fetch.yield_self{|status,head,body|
        if !%w(r u user).member?(r.parts[0]) || status.to_s.match?(/^30/)
          [status, head, body]
        else # find next-page pointer, missing in HTTP Headers (old/new UI) and HTML/RSS (new UI)
          refs = []
          body[0].scan(/href="([^"]+after=[^"]+)/){|l| refs << l[0] }
          if refs.empty?
            [301, {'Location' => ['https://www.reddit.com', r.path, '?', r.query].join}, []]
          else
            page = refs[-1].R
            [302, {'Location' => ['https://www.reddit.com', page.path, '?', page.query].join}, []]
          end
        end}}

    # Reuters
    (0..5).map{|i|
      GET "s#{i}.reutersmedia.net", -> r {
        if (r.query_values||{}).has_key? 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + HTTP.qs(r.query_values.reject{|k,_|k=='w'})}, []]
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

    # Tumblr
    GET '.tumblr.com', -> r {(r.query_values||{}).has_key?('audio_file') ? [301, {'Location' => r.query_values['audio_file']}, []] : NoGunk[r]}
    
    # Twitch
    %w( api gql irc-ws.chat panels-images pubsub-edge www ).map{|h|Allow h + '.twitch.tv'}
    GET 'static.twitchcdn.net'

    # Twitter
    ['', 'api.', 'mobile.'].map{|h| Allow h + 'twitter.com'}

    Populate 'twitter.com', -> r {
      FileUtils.mkdir 'twitter'
      `cd ~/src/WebServer && git show -s --format=%B a3e600d66f2fd850577f70445a0b3b8b53b81e89`.split.map{|n|
        FileUtils.touch 'twitter/.' + n}}

    GET 'api.twitter.com', -> r {
      if r.env.keys.grep(/token/i).empty?
        r.env['HTTP_COOKIE'] = 'twitter/.cookie'.R.readFile
        r.TwitterAuth
      end
      r.fetch}

    Twitter = -> r {
      r.chrono_sort.TwitterAuth
      # feed
      (if r.path == '/'
       subscriptions = Pathname.glob('twitter/.??*').map{|n|n.basename.to_s[1..-1]}
       subscriptions.shuffle.each_slice(18){|sub|
         print '🐦'
         q = sub.map{|u|'from%3A' + u}.join('%2BOR%2B')
         apiURL = 'https://api.twitter.com/2/search/adaptive.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&q=' + q + '&vertical=default&count=40&query_source=&pc=1&spelling_corrections=1&ext=mediaStats%2CcameraMoment'
         apiURL.R(r.env).fetch intermediate: true}
       r.saveRDF.graphResponse
      # user
      elsif r.parts.size == 1 && !%w(favicon.ico manifest.json push_service_worker.js search sw.js).member?(r.parts[0]) && !r.upstreamUI?
        uid = nil
        begin
          URI.open('https://api.twitter.com/graphql/G6Lk7nZ6eEKd7LBBZw9MYw/UserByScreenName?variables=%7B%22screen_name%22%3A%22' + r.parts[0] + '%22%2C%22withHighlightedLabel%22%3Afalse%7D', r.headers){|response| # find uid
            body = HTTP.decompress response.meta, response.read
            json = ::JSON.parse body
            uid = json['data']['user']['rest_id']}
          ('https://api.twitter.com/2/timeline/profile/' + uid + '.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&include_tweet_replies=false&userId=' + uid + '&count=20&ext=mediaStats%2CcameraMoment').R(r.env).fetch reformat: true
        rescue
          [401,{},[]]
        end
      # conversation
      elsif r.parts.member?('status') && !r.upstreamUI?
        convo = r.parts.find{|p| p.match? /^\d{8}\d+$/ }
        "https://api.twitter.com/2/timeline/conversation/#{convo}.json?include_profile_interstitial_type=1&include_blocking=1&include_blocked_by=1&include_followed_by=1&include_want_retweets=1&include_mute_edge=1&include_can_dm=1&include_can_media_tag=1&skip_status=1&cards_platform=Web-12&include_cards=1&include_composer_source=true&include_ext_alt_text=true&include_reply_count=1&tweet_mode=extended&include_entities=true&include_user_entities=true&include_ext_media_color=true&include_ext_media_availability=true&send_error_codes=true&simple_quoted_tweets=true&count=20&ext=mediaStats%2CcameraMoment".R(r.env).fetch reformat: true
      else
        NoGunk[r]
       end).yield_self{|s,h,b|
        if [401,403,429].member? s
          'twitter/.cookie'.R.node.delete # nuke tokens
          r.upstreamUI.fetch
        else
          [s,h,b]
        end}}

    GET 'mobile.twitter.com', Twitter
    GET 'twitter.com', Twitter

    # Viglink
    GET 'redirect.viglink.com', GotoU

    # WaPo
    GET 'www.washingtonpost.com', -> r {(r.parts[0]=='resizer' ? Resizer : NoGunk)[r]}

    # Wix
    GET 'static.parastorage.com'

    # WordPress
    %w(i0 i1 i2 s0 s1 s2).map{|h| host = h + '.wp.com'
      Cookies host
      GET host }

    # WSJ
    %w(images m s).map{|h| GET h + '.wsj.net' }

    # Yahoo!
    %w(finance news www).map{|h| GET h + '.yahoo.com' }

    GET 's.yimg.com', -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        NoGunk[r]
      end}

    # Yelp
    GET 'www.yelp.com', -> r {(r.query_values||{})['redirect_url'] ? [301, {'Location' => r.query_values['redirect_url']},[]] : r.fetch}

    # YouTube
    Cookies 'm.youtube.com'
    Allow 'www.youtube.com'
    GET 'youtube.com', -> r {[301, {'Location' => ['https://www.youtube.com', r.path, '?', r.query].join}, []]}
    GET 'm.youtube.com', -> r {%w(channel feed playlist results user watch watch_comment yts).member?(r.parts[0]) ? r.upstreamUI.fetch : r.deny}
    GET 'img.youtube.com'

    GET 'www.youtube.com', -> r {
      path = r.parts[0]
      if %w{attribution_link redirect}.member? path
        [301, {'Location' => r.query_values['q'] || r.query_values['u']}, []]
      elsif r.path == '/'
        [301, {'Location' => '/feed/subscriptions'}, []]
      elsif %w(browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat manifest.json opensearch playlist results signin user watch watch_videos yts).member?(path) || (r.query_values||{})['allow'] == ServerKey
        NoGunk[r.upstreamUI]
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

  def FourChan doc
    doc.css('.post').map{|post|
      subject = join post.css('.postNum a')[0]['href']
                                         yield subject, Type,    Post.R
      post.css(      '.name').map{|name| yield subject, Creator, name.inner_text }
      post.css(  '.dateTime').map{|date| yield subject, Date,    Time.at(date['data-utc'].to_i).iso8601 }
      post.css(   '.subject').map{|subj| yield subject, Title,   subj.inner_text }
      post.css('.postMessage').map{|msg| yield subject, Content, msg }
      post.css('.fileThumb').map{|thumb| yield subject, Image,   thumb['href'].R if thumb['href']}
      post.remove}
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
    doc.css('div.comment').map{|comment|
      if ts = comment.css('.js-timestamp')[0]
        subject = ts['href'] ? (join ts['href']) : self
        yield subject, Type, Post.R
        if body = comment.css('.comment-body')[0]
          yield subject, Content, Webize::HTML.clean(body.inner_html, self)
        end
        if time = comment.css('[datetime]')[0]
          yield subject, Date, time['datetime']
        end
        if author = comment.css('.author')[0]
          yield subject, Creator, join(author['href'])
          yield subject, Creator, author.inner_text
        end
        yield subject, To, self
        comment.remove
      end
    }
  end

  def Gitter doc
    position = 0
    doc.css('.chat-item').map{|msg|
      id = msg.classes.grep(/^model-id/)[0].split('-')[-1] # find ID
      subject = 'https://gitter.im' + path + '?at=' + id   # subject URI
      yield subject, Type, Post.R
      if from = msg.css('.chat-item__from')[0]
        yield subject, Creator, from.inner_text
      end
      if username = msg.css('.chat-item__username')[0]
        yield subject, Creator, ('https://github.com/' + username.inner_text.sub(/^@/,'')).R
      end
      yield subject, Content, msg.css('.chat-item__text')[0].inner_html
      if image = msg.css('.avatar__image')[0]
        yield subject, Image, image['src'].R
      end
      yield subject, Date, '%03d' % position += 1
      msg.remove }
    doc.css('header').map &:remove
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

  def TwitterAuth
    return self unless env.has_key? 'HTTP_COOKIE'
    attrs = {}
    env['HTTP_COOKIE'].split(';').map{|attr|
      k , v = attr.split('=').map &:strip
      attrs[k] = v}
    env['authorization'] ||= 'Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA'
    env['x-csrf-token'] ||= attrs['ct0'] if attrs['ct0']
    env['x-guest-token'] ||= attrs['gt'] if attrs['gt']
    self
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

  def YouTubeHTML doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
