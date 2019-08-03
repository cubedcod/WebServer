module Webize
  module HTML
    class Reader

      Gunk = %w{
 .ActionBar .ActionBar-items .SocialBar
 .featured-headlines
 .global-audio-components
}
      Triplr = {
        'apnews.com' => :AP,
        'www.apnews.com' => :AP,
        'www.city-data.com' => :CityData,
        'www.instagram.com' => :Instagram,
        'www.patriotledger.com' => :GateHouse,
        'www.providencejournal.com' => :GateHouse,
        'twitter.com' => :Twitter,
        'www.youtube.com' => :YouTube,
      }

    end
  end
  module JSON
    Triplr = {
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
    SiteGIF = ConfDir.join('site.gif').read
    SiteCSS = ConfDir.join('site.css').read
    SiteJS  = ConfDir.join('site.js').read
  end
  module HTTP

    # User-Agent for upstream desktop UI (mobile-browser Desktop-mode toggle to select)
    DesktopUA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.143 Safari/537.36'

    # default to desktop UI
    UIhost = /((anvato|bandcamp|googleapis|jwplatform|(mix|sound)cloud|music.apple|spotify|vimeo).(com|net)|github.io|.tv)$/

    # client UA info sent to origin
    UAhost = /(qualcomm)\.com$/

    # allow cookies (POST/Track/UI hosts also allowed)
    CookieHost = /(qualcomm|twitch|twitter)\.(com|net|tv)$/

    # allow POST
    POSThost = /(^|\.)(amazon(aws)?|anvato|brightcove|google(apis)?|git(lab|ter)|moovitapp|reddit|(mix|sound)cloud|music.apple|ttvnw|api.twitter|twitch|weather|youtube)\.(com|gov|im|net|tv)$/

    # allow paths named 'track'
    TrackHost = /\.(bandcamp|soundcloud|track-blaster)\.com$/

    # verbose request information
    DebugHost = /(amazonaws|amplitude|app-measurement.com|crashlytics|google|linkedin|qualcomm)\.com$/

    def sitePOST
      case host
      when 'metrics.brightcove.com'
        denyPOST
      when /\.soundcloud\.com$/
        if host.match? /^api/
          self.POSTthru
        else
          denyPOST
        end
      when /\.youtube.com$/
        if parts.member? 'stats'
          denyPOST
        elsif env['REQUEST_URI'].match? /ACCOUNT_MENU|comment|\/results|subscribe/
          self.POSTthru
        else
          denyPOST
        end
      when /amazon/
        if !ENV.has_key?('AMAZON')
          denyPOST
        else
          self.POSTthru
        end
      when /google/
        if !ENV.has_key?('GOOGLE')
          denyPOST
        else
          self.POSTthru
        end
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
        parts = r.parts
        case parts[1]
        when nil # inbox
          [302, {'Location' => '/d/*/msg*?head&sort=date&view=table'}, []]
        when /^(to|from)$/ # match slug to address containers
          [302, {'Location' => "/mail/*/*#{parts[2]}*/*?head&sort=date&view=table"}, []]
        else
          r.local # default local handling
        end
      else
        r.remote
      end
    }

    PathGET['/mu']   = -> r {[302, {'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'}, []]}

    PathGET['/resizer'] = -> r {
      parts = r.path.split /\/\d+x\d+\/(filter[^\/]+\/)?/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.remote
      end}

    PathGET['/storyimage'] = -> r {
      parts = r.path.split '&'
      if parts.size > 1
        [301, {'Location' => 'https://' + r.host + parts[0]}, []]
      else
        r.remote
      end}

    PathGET['/url'] = HostGET['gate.sc'] = HostGET['go.skimresources.com'] = -> r {[301,{'Location' => (r.env[:query]['url'] || r.env[:query]['q'])}, []]}

    # AOL
    HostGET['o.aolcdn.com'] = -> r {r.env[:query].has_key?('image_uri') ? [301, {'Location' => r.env[:query]['image_uri']}, []] : r.noexec}

    # Bing
    HostGET['www.bing.com'] = -> r {
      (%w(fd hamburger Identity notifications secure).member?(r.parts[0]) || r.path.index('/api/ping') == 0) ? r.deny : r.desktop.fetch}

    # BusinessWire
    HostGET['cts.businesswire.com'] = -> r {
      r.env[:query].has_key?('url') ? [301, {'Location' => r.env[:query]['url']}, []] : r.deny
    }

    # Cloudflare
    HostGET['cdnjs.cloudflare.com'] = -> r {r.fetch}

    # DartSearch
    HostGET['clickserve.dartsearch.net'] = -> r {[301,{'Location' => r.env[:query]['ds_dest_url']}, []]}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.remote}
    HostGET['proxy.duckduckgo.com'] = -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.env[:query]['u']}, []] : r.remote}

    # eBay
    HostGET['i.ebayimg.com'] = -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.fetch
      end}
    HostGET['rover.ebay.com'] = -> r {r.env[:query].has_key?('mpre') ? [301, {'Location' => r.env[:query]['mpre']}, []] : r.deny}

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {%w{connect pages_reaction_units plugins security tr}.member?(r.parts[0]) ? r.deny : r.noexec}
    HostGET['l.instagram.com'] = HostGET['l.facebook.com'] = -> r {[301, {'Location' => r.env[:query]['u']},[]]}

    # Forbes
    HostGET['thumbor.forbes.com'] = -> r {[301, {'Location' => URI.unescape(r.parts[-1])}, []]}

    # Gitter
    HostGET['gitter.im'] = -> req {req.desktop.remote}

    # Google
    # script hosts
    HostGET['ajax.googleapis.com'] = -> r {r.fetch}
    # static-asset hosts w/o scripts
    %w(
developers.google.com
encrypted-tbn0.gstatic.com
encrypted-tbn1.gstatic.com
encrypted-tbn2.gstatic.com
encrypted-tbn3.gstatic.com
feedproxy.google.com
kh.google.com
maps.gstatic.com
ssl.gstatic.com
www.gstatic.com
).map{|host|
      HostGET[host] = -> r {r.noexec}}
    # misc hosts
    HostGET['feeds.feedburner.com'] = -> r {r.path[1] == '~' ? r.deny : r.noexec}
    HostGET['www.googleadservices.com'] = -> r {r.env[:query]['adurl'] ? [301, {'Location' => r.env[:query]['adurl']},[]] : r.deny}
    HostGET['google.com'] = HostGET['maps.google.com'] = HostGET['maps.googleapis.com'] = HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        r.desktop.fetch
      when 'imgres'
        r.env[:query].has_key?('imgurl') ? [301, {'Location' => r.env[:query]['imgurl']}, []] : r.fetch
      when /images|maps/
        r.desktop.fetch
      when /aclk|search/
        r.fetch
      else
        r.deny
      end}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Outline
    HostGET['outline.com'] = -> r {
      if r.parts[0] == 'favicon.ico'
        r.deny
      else
        graph = RDF::Repository.new
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['SERVER_NAME'] = 'outlineapi.com'
        if r.parts.size == 1
          r.env[:query] = {id: r.parts[0]}
          '/v4/get_article'.R(r.env).fetch graph: graph, no_response: true
        elsif r.env['REQUEST_PATH'][1..5] == 'https'
          r.env[:query] = {source_url: r.env['REQUEST_PATH'][1..-1]}
          '/article'.R(r.env).fetch graph: graph, no_response: true
        end
        r.graphResponse graph
      end}

    # Reddit
    HostGET['reddit.com'] = HostGET['old.reddit.com'] = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    HostGET['www.reddit.com'] = -> r {
      if r.path == '/'
        r.env[:resp]['Refresh'] = 1800
        ('//www.reddit.com/r/' + r.subscriptions.join('+') + '/new').R(r.env).fetch
      else
        r.remote
      end}

    # Reuters
    (0..5).map{|i|
      HostGET["s#{i}.reutersmedia.net"] = -> r {
        if r.env[:query].has_key? 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + HTTP.qs(r.env[:query].reject{|k,_|k=='w'})}, []]
        else
          r.noexec
        end}}

    # Soundcloud
    HostGET['api-v2.soundcloud.com'] = -> r {
      re = HTTParty.get ('https://' + r.host + r.path + r.qs), headers: r.headers
      [re.code, re.headers, [re.body]]}

    # Twitter
    HostGET['mobile.twitter.com'] = -> r {[301,{'Location' => 'https://twitter.com' + r.path },[]]}
    HostGET['t.co'] = -> r {r.parts[0] == 'i' ? r.deny : r.noexec}
    HostGET['twitter.com'] = -> r {
      r = r.R
      if !r.path || r.path == '/'
        if !r.env # REPL / script caller
          r.env({resp: {}}) # initialize environment
          no_response = true # no HTTP return-value
        end
        r.env[:resp]['Refresh'] = 1800 # client refresh hint

        graph = RDF::Repository.new
        fetch_options = {
          graph: graph,
          no_embeds: true, # skip HTML RDF-embeds if any, use custom parser
          no_index: true, # don't index during fetch
          no_response: true} # no HTTP return-value from fetch

        '//twitter.com'.R.subscriptions.shuffle.each_slice(18){|s|
          r.env[:query] = { vertical: :default, f: :tweets, q: s.map{|u|'from:' + u}.join('+OR+')}
          '//twitter.com/search'.R(r.env).fetch fetch_options}
        updates = r.index graph

        # return value
        no_response ? updates : (r.graphResponse graph)
      else
        r.remote
      end}

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
    HostGET['youtu.be'] = -> re {[301, {'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]}, []]}
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode || %w{
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
}.member?(mode)
        r.desktop.fetch cookies: true
      elsif %w{attribution_link redirect}.member? mode
        [301, {'Location' =>  r.env[:query]['q'] || r.env[:query]['u']},[]]
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
            month, day, year = date.split '-'
          end
          time, ampm = timeAP.strip.split ' '
          hour, min = time.split ':'
          hour = hour.to_i
          pm = ampm == 'PM'
          hour += 12 if pm
          yield subject, Date, "#{year}-#{'%02d' % month}-#{day}T#{'%02d' % hour}:#{min}:00+00:00"
        end
      end
      post.remove }
    %w{#fixed_sidebar}.map{|sel|
      (doc.css sel).map{|_| _.remove}}
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

  IGgraph = /^window._sharedData = /
  def Instagram doc
    doc.css('script').map{|script|
      if script.inner_text.match? IGgraph
        graph = ::JSON.parse script.inner_text.sub(IGgraph,'')[0..-2]
        Webize::HTML.webizeHash(graph){|h|
          if h['shortcode']
            #puts ::JSON.pretty_generate h
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
              yield s, Abstract, (CGI.escapeHTML text)
            end rescue nil
          end}
      end}
  end

  def Outline tree
    subject = tree['data']['article_url']
    yield subject, Type, Post.R
    yield subject, Title, tree['data']['title']
    yield subject, To, ('//' + tree['data']['domain']).R
    yield subject, Content, (Webize::HTML.clean tree['data']['html'])
    yield subject, Image, tree['data']['meta']['og']['og:image'].R
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

    doc.css('body').remove
  end

  def YouTube doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
