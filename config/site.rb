class WebResource
  module HTML
    class Reader
      Gunk = %w{
 .ActionBar .ActionBar-items .SocialBar
 .featured-headlines
 .global-audio-components
}
    end
  end
  module HTTP

    # UA must match this to request upstream UI. on mobile choose "Desktop Site" in browser menu
    DesktopUA = 'Mozilla/5.0 (X11; Linux x86_64; rv:67.0) Gecko/20100101 Firefox/67.0'

    # hosts with dirs named 'track'
    TrackHost = /\.(bandcamp|soundcloud|theplatform|track-blaster)\.com$/

    # POSTs, allow in regex and define handler if needed
    POSThost = /(^|\.)(anvato|brightcove|(accounts|android.*|clients?[0-9]*|drive|groups|images|mail|maps|photos|www|youtubei?)\.google(apis)?|reddit|soundcloud|youtube|zillow)\.(com|net)$/
    def sitePOST
      case host
      when 'www.facebook.com'
        if %w{/api/graphql/}.member? path
          self.POSTthru
        else
          denyPOST
        end
      when /\.google\.com$/
        if path.match? /searchbyimage|signin/
          self.POSTthru
        else
          denyPOST
        end
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
    PathGET['/mu']  = -> r {[301,{'Location' => '/d/*/*{[Bb]oston{hassle,hiphop,music},artery,cookland,funkyfresh,getfamiliar,graduationm,hipstory,ilovemyfiends,inthesoil,killerb,miixtape,onevan,tmtv,wrbb}*'}, []]}
    PathGET['/resizer'] = -> r {
      parts = r.path.split /\/\d+x\d+\//
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.remote
      end}
    PathGET['/url'] = HostGET['gate.sc'] = HostGET['go.skimresources.com'] = -> r {[301,{'Location' => (r.q['url'] || r.q['q'])}, []]}

    # DuckDuckGo
    HostGET['duckduckgo.com'] = -> r {%w{ac}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['proxy.duckduckgo.com'] = -> r {%w{iu}.member?(r.parts[0]) ? [301, {'Location' => r.q['u']}, []] : r.remote}

    # eBay
    HostGET['i.ebayimg.com'] = -> r {
      if r.basename.match? /s-l(64|96|200|225).jpg/
        [301, {'Location' => r.dirname + '/s-l1600.jpg'}, []]
      else
        r.fetch
      end}

    # Facebook
    HostGET['facebook.com'] = HostGET['www.facebook.com'] = -> r {%w{connect pages_reaction_units plugins security tr}.member?(r.parts[0]) ? r.drop : r.remote}
    HostGET['l.instagram.com'] = HostGET['l.facebook.com'] = -> r {[301, {'Location' => r.q['u']},[]]}

    # Gitter
    HostGET['gitter.im'] = -> req {req.env['HTTP_USER_AGENT'] = DesktopUA; req.remote}

    # Google
    (0..3).map{|i|HostGET["encrypted-tbn#{i}.gstatic.com"] = -> r {r.noexec}}
    HostGET['ajax.googleapis.com'] = HostGET['cdnjs.cloudflare.com'] = -> r {r.fetch}     # allow JS libraries
    HostGET['feedproxy.google.com'] = HostGET['storage.googleapis.com'] = -> r {r.noexec} # filter jungle JS
    HostGET['feeds.feedburner.com'] = -> r {r.path[1] == '~' ? r.drop : r.noexec}
    HostGET['google.com'] = HostGET['maps.google.com'] = HostGET['maps.googleapis.com'] = HostGET['www.google.com'] = -> req {
      mode = req.parts[0]
      search = mode == 'search'
      if %w{async complete js recaptcha searchdomaincheck xjs}.member? mode
        req.drop
      elsif mode == 'maps'
        req.env['HTTP_USER_AGENT'] = DesktopUA
        req.GETthru
      else
        case req.env['HTTP_TYPE']
        when /dropURI/
          req.drop
        else
          if OFFLINE && search # search local index
            [302, {'Location' => 'http://localhost:8000/m' + req.qs}, []]
          else                 # fetch
            req.fetch.do{|status, head, body|
              case status
              when 403 # blocked by a middlebox, try DDG
                [302, {'Location' => 'https://duckduckgo.com/' + req.qs}, []]
              else
                [status, head, body]
              end}
          end
        end
      end}
    HostGET['www.googleadservices.com'] = -> r {r.q['adurl'] ? [301, {'Location' => r.q['adurl']},[]] : r.drop}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Outline
    HostGET['outline.com'] = -> r {
      if r.parts.size == 1 && r.parts[0] != 'favicon.ico'
        r.env['HTTP_HOST'] = 'outlineapi.com'
        r.env['REQUEST_URI'] = '/v4/get_article?id=' + r.parts[0]
        r.fetch
      else
        r.drop
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

    # Twitter
    HostGET['twitter.com'] = -> r {
      if !r.path || r.path == '/'
        graph = RDF::Repository.new
        r.subscriptions.shuffle.each_slice(18){|s|
          ('https://twitter.com/search?f=tweets&vertical=default&q='+s.map{|u|'from:' + u}.intersperse('+OR+').join).R.fetch graph: graph, no_response: true}
        r.graphResponse graph
      else
        r.remote
      end}

    HostGET['s.yimg.com'] = -> r {
      parts = r.path.split /https?:\/+/
      if parts.size > 1
        [301, {'Location' => 'https://' + parts[-1]}, []]
      else
        r.drop
      end}

    # YouTube
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
        r.env['HTTP_USER_AGENT'] = DesktopUA
        r.fetch cookies: true
      elsif %w{attribution_link redirect}.member? mode
        [301, {'Location' =>  r.q['q'] || r.q['u']},[]]
      else
        r.drop
      end}

  end

  def self.twits
    `cd ~/src/WebServer && git show -s --format=%B f8f21ef33eaa3fba034d9868d3bc4cd2f68bede4`.split.map{|twit|
      ('https://twitter.com/' + twit).R.subscribe}
  end

  module Webize

    def AP doc
      doc.css('script').map{|script|
        script.inner_text.scan(/window\['[-a-z]+'\] = ([^\n]+)/){|data|
          data = data[0]
          data = data[0..-2] if data[-1] == ';'
          json = ::JSON.parse data
          yield self, Content, HTML.render(HTML.keyval (HTML.webizeHash json), env)}}
    end

    GHgraph = /__gh__coreData.content=(.*?)\s*__gh__coreData.content.bylineFormat/m
    def GateHouse doc
      doc.css('script').map{|script|
        if data = script.inner_text.match(GHgraph)
          graph = ::JSON.parse data[1][0..-2]
          HTML.webizeHash(graph){|h|
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
          HTML.webizeHash(graph){|h|
            if h['shortcode']
              #puts ::JSON.pretty_generate h
              s = 'https://www.instagram.com/p/' + h['shortcode']
              yield s, Type, Post.R
              yield s, Image, h['display_url'].R if h['display_url']
              h['owner'].do{|o|
                yield s, Creator, ('https://www.instagram.com/' + o['username']).R
                yield s, To, 'https://www.instagram.com/'.R
              }
              h['edge_media_to_caption']['edges'][0]['node']['text'].do{|t|
                yield s, Abstract, CGI.escapeHTML(t)
              } rescue nil
            end}
        end}
    end

    def Outline tree
      subject = tree['data']['article_url']
      yield subject, Type, Post.R
      yield subject, Title, tree['data']['title']
      yield subject, To, ('//' + tree['data']['domain']).R
      yield subject, Content, (HTML.clean tree['data']['html'])
      yield subject, Image, tree['data']['meta']['og']['og:image'].R
    end

    def Twitter doc
      %w{grid-tweet tweet}.map{|tweetclass|
      doc.css('.' + tweetclass).map{|tweet|
        s = 'https://twitter.com' + (tweet.css('.js-permalink').attr('href') || tweet.attr('data-permalink-path'))
        authorName = tweet.css('.username b')[0].do{|b|b.inner_text} || s.R.parts[0]
        author = ('https://twitter.com/' + authorName).R
        ts = (tweet.css('[data-time]')[0].do{|unixtime|
                Time.at(unixtime.attr('data-time').to_i)} || Time.now).iso8601
        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, 'https://twitter.com'.R
        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'link'+rand.to_s.sha2)
            a.set_attribute('href', 'https://twitter.com' + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
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
    Triplr = {}
    Triplr[:HTML] = {
      'apnews.com' => :AP,
      'www.apnews.com' => :AP,
      'www.instagram.com' => :Instagram,
      'www.patriotledger.com' => :GateHouse,
      'twitter.com' => :Twitter,
      'www.youtube.com' => :YouTube,
    }
    Triplr[:JSON] = {
      'outline.com' => :Outline,
      'outlineapi.com' => :Outline,
      'www.youtube.com' => :YouTubeJSON,
    }

    include URIs
  end
  include Webize
end
