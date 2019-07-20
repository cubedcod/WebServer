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
    ConfDir  = (Pathname.new __dir__).relative_path_from PWD

    FeedURL = {}
    ConfDir.join('feeds/*.u').R.glob.map{|list|
      list.lines.map{|u|
        FeedURL[u] = u.R }}

    SiteGIF = ConfDir.join('site.gif').read
    SiteCSS = ConfDir.join('site.css').read
    SiteJS  = ConfDir.join('site.js').read

  end
  module HTTP

    DesktopUA = 'Mozilla/5.0 (X11; Linux RISC-V; rv:69.0) Gecko/20100101 Firefox/69.0'
    ImmutableFormat = /^application\/json/
    POSThost = /(^|\.)(anvato|brightcove|git(lab|ter)|reddit|(mix|sound)cloud|youtube)\.(com|im|net)$/
    TrackHost = /\.(bandcamp|soundcloud|track-blaster)\.com$/
    UIhost = /(anvato|bandcamp|(mix|sound)cloud|spotify).(com|net)$/

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
      when 'youtubei.googleapis.com'
        if path.match? /\/log/
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

    # redirects
    PathGET['/mu']  = -> r {[302,
     {'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'}, []]}

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

    PathGET['/url'] = HostGET['gate.sc'] = HostGET['go.skimresources.com'] = -> r {[301,{'Location' => (r.q['url'] || r.q['q'])}, []]}

    # Bing
    HostGET['www.bing.com'] = -> r {
      (%w(fd hamburger Identity notifications secure).member?(r.parts[0]) || r.path.index('/api/ping') == 0) ? r.deny : r.desktop.fetch}

    # BusinessWire
    HostGET['cts.businesswire.com'] = -> r {
      r.q.has_key?('url') ? [301, {'Location' => r.q['url']}, []] : r.deny
    }

    # DartSearch
    HostGET['clickserve.dartsearch.net'] = -> r {[301,{'Location' => r.q['ds_dest_url']}, []]}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.deny : r.remote}
    HostGET['proxy.duckduckgo.com'] = -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.q['u']}, []] : r.remote}

    # eBay
    HostGET['i.ebayimg.com'] = -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.fetch
      end}
    HostGET['rover.ebay.com'] = -> r {r.q.has_key?('mpre') ? [301, {'Location' => r.q['mpre']}, []] : r.deny}

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {%w{connect pages_reaction_units plugins security tr}.member?(r.parts[0]) ? r.deny : r.remote}
    HostGET['l.instagram.com'] = HostGET['l.facebook.com'] = -> r {[301, {'Location' => r.q['u']},[]]}

    # Gitter
    HostGET['gitter.im'] = -> req {req.desktop.remote}

    # Google
    (0..3).map{|i|
      HostGET["encrypted-tbn#{i}.gstatic.com"] = -> r {r.noexec}}
    HostGET['feedproxy.google.com'] = -> r {r.noexec}
    HostGET['feeds.feedburner.com'] = -> r {r.path[1] == '~' ? r.deny : r.noexec}
    HostGET['google.com'] = HostGET['maps.google.com'] = HostGET['maps.googleapis.com'] = HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        r.desktop.fetch
      when 'imgres'
        r.q.has_key?('imgurl') ? [301, {'Location' => r.q['imgurl']}, []] : r.fetch
      when /images|maps/
        r.desktop.fetch
      when /aclk|search/
        r.fetch
      else
        r.deny
      end}
    HostGET['www.googleadservices.com'] = -> r {r.q['adurl'] ? [301, {'Location' => r.q['adurl']},[]] : r.deny}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Outline
    HostGET['outline.com'] = -> r {
      if r.parts.size == 1 && r.parts[0] != 'favicon.ico'
        r.env['HTTP_ORIGIN'] = 'https://outline.com'
        r.env['HTTP_REFERER'] = r.env['HTTP_ORIGIN'] + r.path
        r.env['HTTP_HOST'] = 'outlineapi.com'
        r.env['REQUEST_URI'] = '/v4/get_article?id=' + r.parts[0]
        r.fetch
      else
        r.deny
      end}

    # Reddit
    HostGET['reddit.com'] = -> r {[301, {'Location' =>  'https://www.reddit.com' + r.path},[]]}
    HostGET['www.reddit.com'] = -> r {
      if r.path == '/'
        ('//www.reddit.com/r/' + r.subscriptions.join('+') + '/new').R(r.env).fetch
      else
        r.remote
      end}

    # Reuters
    (0..5).map{|i|
      HostGET["s#{i}.reutersmedia.net"] = -> r {
        if r.q.has_key? 'w'
          q = r.q
          q.delete 'w'
          [301, {'Location' =>  r.env['REQUEST_PATH'] + (HTTP.qs q)}, []]
        else
          r.noexec
        end}}

    # Soundcloud
    HostGET['api-v2.soundcloud.com'] = -> r {
      re = HTTParty.get ('https://' + r.host + r.path + r.qs), headers: r.headers
      [re.code, re.headers, [re.body]]}

    # Twitter
    HostGET['t.co'] = -> r {r.parts[0] == 'i' ? r.deny : r.noexec}
    HostGET['twitter.com'] = -> r {
      if !r.path || r.path == '/'
        graph = RDF::Repository.new
        r.subscriptions.shuffle.each_slice(18){|s|
          ('https://twitter.com/search?f=tweets&vertical=default&q='+s.map{|u|'from:' + u}.join('+OR+')).R.fetch graph: graph, no_response: true}
        r.graphResponse graph
      else
        r.remote
      end}

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
        r.deny
      end}

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
        [301, {'Location' =>  r.q['q'] || r.q['u']},[]]
      else
        r.deny
      end}

  end
  def self.twits
    `cd ~/src/WebServer && git show -s --format=%B f8f21ef33eaa3fba034d9868d3bc4cd2f68bede4`.split.map{|twit|
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
              yield s, Creator, ('https://www.instagram.com/' + owner['username']).R
              yield s, To, 'https://www.instagram.com/'.R
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

        authorName = if b = tweet.css('.username b')[0]
                       b.inner_text
                     else
                       s.R.parts[0]
                     end
        author = ('https://twitter.com/' + authorName).R

        ts = (if unixtime = tweet.css('[data-time]')[0]
              Time.at(unixtime.attr('data-time').to_i)
             else
               Time.now
              end).iso8601

        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, 'https://twitter.com'.R
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
          yield s, Image, img.attr('src').to_s.R}}}
  end

  def YouTube doc
    yield self, Video, self if path == '/watch'
  end

  def YouTubeJSON doc

  end

end
