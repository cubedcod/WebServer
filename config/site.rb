module Webize
  module HTML
    class Reader

      Gunk = %w( .ActionBar .SocialBar )

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
    ConfDir  = (Pathname.new __dir__).relative_path_from Pathname.new Dir.pwd
    Extensions = RDF::Format.file_extensions.invert
    FeedURL = {}
    ConfDir.join('feeds/*.u').toWebResource.glob.map{|list|
      (open list.relPath).readlines.map(&:chomp).map{|u|
        FeedURL[u] = u.R }}
    ServerAddr = 'http://localhost:8000'
    SiteFont = ConfDir.join('fonts/hack-regular-subset.woff2').read
    SiteGIF = ConfDir.join('site.gif').read
    SiteCSS = ConfDir.join('site.css').read
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
    CDNhost = /amazon|azure|cloud(flare|front|inary)|digitalocean|fa(cebook|stly)|heroku|jsdelivr|netdna|ra(ckcdn|wgit)|stackpath|usercontent/
    DesktopUA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3896.4 Safari/537.36'
    CookieHost = /(bandcamp|bizjournals|brightcove|google|reddit|twi(tch|tter)|youtube)\.(com|net|tv)$/
    GunkURI = /[-.:_\/?&=~](([Bb]lock|[Pp]age)?[Aa](d(vert(i[sz](ement|ing))?)?|ffiliate|nalytic)s?([Bb]lock(er|ing)?.*|id|[Ww]ords?)?|([Aa]pp)?[Bb](anner|eacon)s?|[Cc](ampaign|edexis|hart[Bb]eat.*|om[Ss]core|ookie([Cc](hoices|onsent)|[Ll]aw|[Nn]otice)?|ount|se)|[Ee](moji.*\.js|nsighten|vidon)|([Ww]eb)?[Ff]onts?|\.gif\?|[Gg]([dD][pP][rR]|eo(ip|locate)|igya|[Pp][Tt]|tag|[Tt][Mm])|.*([Hh]eader|[Pp]re)[-_]?[Bb]id.*|.*[Hh]ub[Ss]pot.*|[hp]b.?js|ima[0-9]?|[Kk]r(ux|xd).*|logger|([Aa]pp|s)?[Mm](e(asurement|t(er|rics?))|ms|tr)|[Nn]ew([Rr]elic|sletter)|[Oo](m(niture|tr)|nboarding|ptanon|utbrain)|[Pp](ay(ments?|[Ww]all)|ersonaliz(ation|e)|i(wik|xel(propagate)?)|op(over|up)|romo(tion)?s?|[vx])|[Qq]uant[Cc]ast|[Rr]eco(mmend(ed)?|rd([Ee]vent|[Ss]tats?)?)|s?[Ss](a(fe[-_]?[Bb]rowsing|ilthru)|ervice[-_]?[Ww]orker|i(ftscience|gnalr|tenotice)|o(cial|urcepoint)|ponsored|so|tat(istic)?s?|ubscri(ber?|ption)|w.js|ync)|[Tt](aboola|(arget|rack)(ers?|ing)?|bproxy|ea(lium|ser)|rend(ing|s))|[Uu](rchin|[Tt][Mm])|wp-rum)([-._\/?&=]|$)|\.((gif|png)\?|otf|ttf|woff2?)/
    MediaHost = /\.(api.brightcove|bandcamp|soundcloud|track-blaster|usps)\.com$/
    POSThost = /(^|\.)(amazon(aws)?|anvato|brightcove|dailymotion|facebook|google(apis)?|git(lab|ter)|mixcloud|(music|xp).apple|postimages|reddit|shazam|twitter|api.soundcloud|ttvnw|twitch|youtube)\.(com|gov|im|net|org|tv)$/
    POSTpath = /\/graphql([\/]|$)/
    UAhost = /android|mozilla/
    UIhost = /((apple|anvato|bandcamp|books.google|boston25news|brightcove|duckduckgo|gannettdigital|iheart|jwplatform|(mix|sound)cloud|miixtapechiick|postimages|spotify|uw-media.thenews-messenger|vimeo|wcvb|youtube).(com|net|org)|github.io|.tv)$/
    UIpath = /oembed\./

    def sitePOST
      case host
      when 'metrics.brightcove.com'
        denyPOST
      when /\.youtube.com$/
        if parts.member? 'stats'
          denyPOST
        elsif env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/
          self.POSTthru
        else
          denyPOST
        end
      when /amazon(aws)?.com$/
        ENV.has_key?('AMAZON') ? self.POSTthru : denyPOST
      when /facebook.(com|net)$/
        ENV.has_key?('FACEBOOK') ? self.POSTthru : denyPOST
      when /google(apis)?.com$/
        if ENV.has_key?('GOOGLE') && host != 'play.google.com'
          self.POSTthru
        else
          denyPOST
        end
      when /(firefox|mozilla).(com|net|org)$/
        ENV.has_key?('MOZILLA') ? self.POSTthru : denyPOST
      else
        self.POSTthru
      end
    end

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

    # path handlers

    PathGET['/mail'] = -> r {
      if r.local?
        if r.path=='/mail' # inbox
          [302, {'Location' => '/d/*/msg*?head&sort=date&view=table'}, []]
        else
          r.local # default local handling
        end
      else
        r.fetch
      end}

    PathGET['/favicon.ico'] = -> _ {[200, {'Content-Type' => 'image/gif'}, [SiteGIF]]}

    PathGET['/resizer'] = -> r {
      parts = r.path.split /\/\d+x\d+\/(filter[^\/]+\/)?/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.fetch
      end}

    PathGET['/storyimage'] = -> r {
      parts = r.path.split '&'
      if parts.size > 1
        [301, {'Location' => 'https://' + r.host + parts[0]}, []]
      else
        r.fetch
      end}

    PathGET['/thumbnail'] = -> r {r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.noexec}

    PathGET['/url'] = HostGET['gate.sc'] = HostGET['go.skimresources.com'] = -> r {[301,{'Location' => (r.env[:query]['url'] || r.env[:query]['q'])}, []]}

    # Alibaba
    %w(www.aliexpress.com ae-cn.alicdn.com ae01.alicdn.com i.alicdn.com).map{|h| HostGET[h] = -> r {r.allowHost}}

    # Amazon
    HostGET['amazon.com'] = HostGET['www.amazon.com'] = -> r {r.allowHost}
    %w(media-amazon.com
  ssl-images-amazon.com
       s3.amazonaws.com).map{|n|Subdomain[n] = -> r {ENV.has_key?('AMAZON') ? r.allowHost : r.noexec}}

    # AOL
    HostGET['o.aolcdn.com'] = -> r {r.env[:query].has_key?('image_uri') ? [301, {'Location' => r.env[:query]['image_uri']}, []] : r.noexec}

    # Bing
    HostGET['www.bing.com'] = -> r {
      (%w(fd hamburger Identity notifications secure).member?(r.parts[0]) || r.path.index('/api/ping') == 0) ? r.deny : r.desktop.fetch}

    # Brightspot
    HostGET['ca-times.brightspotcdn.com'] = -> r {r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.noexec}

    # BusinessWire
    HostGET['cts.businesswire.com'] = -> r {
      r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.deny
    }

    # BuzzFeed
    HostGET['img.buzzfeed.com'] = -> r {r.noexec}
    HostGET['www.buzzfeed.com'] = -> r {r.allowHost}

    # Cloudflare
    HostGET['cdnjs.cloudflare.com'] = -> r {r.fetch}

    # CNN
    HostGET['dynaimage.cdn.cnn.com'] = -> r {[301, {'Location' => CGI.unescape(r.basename)}, []]}

    # DartSearch
    HostGET['clickserve.dartsearch.net'] = -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.fetch}
    HostGET['proxy.duckduckgo.com'] = -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.fetch}

    # eBay
    HostGET['ebay.com'] = HostGET['www.ebay.com'] = -> r {r.allowHost}
    HostGET['i.ebayimg.com'] = -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.noexec
      end}
    HostGET['ir.ebaystatic.com'] = -> r {r.noexec}
    HostGET['rover.ebay.com'] = -> r {r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # Economist
    HostGET['www.economist.com'] = -> r {r.allowHost}

    # Facebook
    FBgunk = %w(common connect pages_reaction_units plugins security tr)
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {ENV.has_key?('FACEBOOK') ? r.fetch : (FBgunk.member? r.parts[0]) ? r.deny : r.noexec}
    HostGET['l.instagram.com'] = HostGET['l.facebook.com'] = -> r {[301, {'Location' => r.env[:query]['u']},[]]}

    # Forbes
    HostGET['thumbor.forbes.com'] = -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    # Gitter
    HostGET['gitter.im'] = -> req {req.desktop.fetch}

    # Google
    Google = -> r {ENV.has_key?('GOOGLE') ? r.fetch : r.noexec}
    HostGET['ajax.googleapis.com'] = -> r {r.allowHost}
    HostGET['feeds.feedburner.com'] = -> r {r.path[1] == '~' ? r.deny : Google[r]}
    HostGET['www.google.com'] = -> r {
      app = r.parts[0]
      if [nil,*%w(aclk images imgres maps search)].member? app
        if 'maps' == app
          r.desktop.fetch
        elsif 'search' == app && r.env[:query]['q']&.match?(/^https?:\/\//) # why is Chrome on android sending HTTP URLs in URL-bar to google search? is it just a search bar now?
          [301, {'Location' => r.env[:query]['q']}, []]
        else
          Google[r]
        end
      else
        r.deny
      end}
    HostGET['www.googleadservices.com'] = -> r {r.env[:query]['adurl'] ? [301, {'Location' => r.env[:query]['adurl']},[]] : r.deny}
    %w(storage.googleapis.com gstatic.com).map{|n| Subdomain[n] = Google }
    %w(accounts.google.com
android.clients.google.com
           apis.google.com
          books.google.com
         chrome.google.com
     developers.google.com
          drive.google.com
encrypted-tbn0.gstatic.com
encrypted-tbn1.gstatic.com
encrypted-tbn2.gstatic.com
encrypted-tbn3.gstatic.com
      feedproxy.google.com
                google.com
         images.google.com
         groups.google.com
             kh.google.com
           maps.google.com
       maps.googleapis.com
          maps.gstatic.com
           ssl.gstatic.com
 suggestqueries.google.com
        www.googleapis.com
           www.gstatic.com
).map{|h| HostGET[h] = Google }

    # Linkedin
    HostGET['www.linkedin.com'] = HostGET['media.licdn.com'] = -> r {r.allowHost}

    # Medium
    #HostGET['medium.com'] = -> r {r.env[:query].has_key?('redirecturl') ? [301, {'Location' => r.env[:query]['redirecturl']}, []] : r.noexec}

    # Meredith Corp
    HostGET['imagesvc.meredithcorp.io'] = -> r {r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.noexec}

    # Mozilla
    Mozilla = -> r {ENV.has_key?('MOZILLA') ? r.fetch : r.deny}
    %w( addons.mozilla.org
addons-amo.cdn.mozilla.net
    addons.cdn.mozilla.net
).map{|h| HostGET[h] = Mozilla }
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # NYTimes
    %w(cooking.nytimes.com
           www.nytimes.com).map{|host|
      HostGET[host] = -> r {r.allowHost}}

    # Outline
    HostGET['outline.com'] = -> r {
      if r.parts[0] == 'favicon.ico'
        r.deny
      else
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['SERVER_NAME'] = 'outlineapi.com'
        if r.parts.size == 1
          r.env[:query] = {id: r.parts[0]}
          '/v4/get_article'.R(r.env).fetch no_response: true
        elsif r.env['REQUEST_PATH'][1..5] == 'https'
          r.env[:query] = {source_url: r.env['REQUEST_PATH'][1..-1]}
          '/article'.R(r.env).fetch no_response: true
        end
        r.graphResponse
      end}

    # Reddit
    HostGET['reddit.com'] = HostGET['old.reddit.com'] = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    HostGET['www.reddit.com'] = -> r {
      r.env[:suffix] = '.rss' if r.ext.empty? && !r.upstreamUI?
      r.env[:query]['sort'] ||= 'date'
      r.env[:query]['view'] ||= 'table'
      r.path == '/' ? ('/r/' + r.subscriptions.join('+') + '/new').R(r.env).fetch : r.allowHost}

    # Reuters
    (0..5).map{|i|
      HostGET["s#{i}.reutersmedia.net"] = -> r {
        if r.env[:query].has_key? 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + HTTP.qs(r.env[:query].reject{|k,_|k=='w'})}, []]
        else
          r.noexec
        end}}

    # Shopify
    HostGET['cdn.shopify.com'] = -> r {r.noexec}

    # Soundcloud
    HostGET['api-v2.soundcloud.com'] = -> r {
      re = HTTParty.get ('https://' + r.host + r.path + r.qs), headers: r.headers
      [re.code, re.headers, [re.body]]}

    # Twitter
    HostGET['mobile.twitter.com'] = -> r {[301,{'Location' => 'https://twitter.com' + r.path },[]]}
    HostGET['t.co'] = -> r {r.parts[0] == 'i' ? r.deny : r.noexec}
    HostGET['twitter.com'] = -> r {
      if !r.path || r.path == '/'
        r.env[:resp]['Refresh'] = 3600 # client refresh hint
        fetch_options = {
          no_embeds: true,   # skip HTML+RDF-embed parse
          no_index: true,    # defer indexing
          no_response: true} # no forwarded HTTP response from fetch
        r.env[:query_modified] = true

        '//twitter.com'.R.subscriptions.shuffle.each_slice(18){|s|
          r.env[:query] = { vertical: :default, f: :tweets, q: s.map{|u|'from:' + u}.join('+OR+')}
          '//twitter.com/search'.R(r.env).fetch fetch_options}
        r.index
        r.graphResponse
      else
        r.allowHost
      end}
    HostGET['api.twitter.com'] = -> r {r.allowHost}
    # WGBH
    HostGET['wgbh.brightspotcdn.com'] = -> r {r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.noexec}

    # WordPress
    HostGET['i0.wp.com'] = HostGET['i1.wp.com'] = HostGET['i2.wp.com'] = -> r {
      r.qs.empty? ? r.noexec : [301, {'Location' => r.env['REQUEST_PATH']}, []]
    }

    # Yahoo!
    HostGET['s.yimg.com'] = -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.noexec
      end}

    # Yelp
    HostGET['www.yelp.com'] = -> r {r.env[:query]['redirect_url'] ? [301, {'Location' => r.env[:query]['redirect_url']},[]] : r.noexec}

    # YouTube
    HostGET['s.ytimg.com'] = -> r {r.desktop.noexec}
    HostGET['youtu.be'] = -> r {[301, {'Location' => 'https://www.youtube.com/watch?v=' + r.path[1..-1]}, []]}
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if %w{attribution_link redirect}.member? mode
        [301, {'Location' =>  r.env[:query]['q'] || r.env[:query]['u']},[]]
      elsif !mode || %w(
browse_ajax
c
channel
embed
feed
get_video_info
guide_ajax
heartbeat
iframe_api
live_chat
playlist
results
signin
user
watch
watch_videos
yts
).member?(mode)
        r.fetch
      else
        r.deny
      end}

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
