class WebResource
  module URIs
    # TODO see if we can block origin headers in squid rules so they can't fake these headers to defeat categorization
    # while also not having the blocked-response-header rules block headers we add. so for now just do it here until delving into squid-config space

    # use sharded-hash path structure, ignore upstream path arrangement
    FlatMap = %w{
a.thumbs.redditmedia.com
b.thumbs.redditmedia.com
i.redd.it
mail.google.com
maps.google.com
www.google.com
www.gstatic.com
www.rfa.org
}

    InsecureShorteners = %w{
bhne.ws
bos.gl
feeds.reuters.com
f-st.co
huffp.st
ihe.art
nyer.cm
ow.ly
rss.cnn.com
rssfeeds.usatoday.com
w.bos.gl
}

    # extensions enabled storage handler
    MediaFormats = %w{css html jpg jpg:large jpeg ogg opus m4a mp3 mp4 pdf png png:large svg txt webm webp woff2}

    # .js and other (or missing) extensions by default disallowed in storage handler
    StoreItAll = %w{
ajax.googleapis.com
cdn.bitmovin.com
content.jwplatform.com
encrypted-tbn0.gstatic.com
forum.solidproject.org
geo0.ggpht.com
geo1.ggpht.com
geo2.ggpht.com
geo3.ggpht.com
github.com
ssl.gstatic.com
static1.squarespace.com
www.cnet.com
www.gstatic.com
www.mixcloud.com
yt3.ggpht.com}

    UpstreamFormat = %w{
api-v2.soundcloud.com
bandcamp.com
mail.google.com
s.ytimg.com
soundcloud.com
www.instagram.com
www.google.com
www.youtube.com
}
    UpstreamToggle = {}

  end
  module HTTP

    def amp
      if MediaFormats.-(['html']).member? ext
        cloudStorage
      else
        [302, {'Location' => 'https://' + (host.split('.') - %w{amp}).join('.') + (path.split('/') - %w{amp amphtml}).join('/')}, []]
      end
    end

    def cloudStorage
      if UpstreamToggle[@r['SERVER_NAME']] || StoreItAll.member?(host) || MediaFormats.member?(ext.downcase)
        remoteNode
      else
        deny
      end
    end

    def HTTPthru
      HostGET[host] = -> r {r.GETthru}
     HostPOST[host] = -> r {r.POSTthru}
  HostOPTIONS[host] = -> r {r.OPTIONSthru}
    end

    def OPTIONSthru
      verbose = false

      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      HTTP.print_header headers if verbose
      HTTP.print_body body, headers['Content-Type'] if verbose

      # response
      r = HTTParty.options url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      HTTP.print_header h if verbose
      HTTP.print_body b, h['Content-Type'] if verbose
      [s, h, [b]]
    end

    def POSTthru
      # request
      url = 'https://' + host + path + qs
      headers = HTTP.unmangle env
      body = env['rack.input'].read
      #HTTP.print_header headers
      #HTTP.print_body body, headers['Content-Type']

      # response
      r = HTTParty.post url, :headers => headers, :body => body
      s = r.code
      h = r.headers
      b = r.body
      #HTTP.print_header h
      #HTTP.print_body b, h['Content-Type']
      [s, h, [b]]
    end

    # request remote resource, index + cache it locally
    def remoteNode
      head = HTTP.unmangle env
      head.delete 'Host'
      formatSuffix = (host.match?(/reddit.com$/) && !parts.member?('w')) ? '.rss' : ''
      useExtension = %w{aac atom css html jpg js mp3 mp4 ogg opus pdf png rdf svg ttf ttl webm webp woff woff2}.member? ext.downcase
      portNum = port && !([80,443,8000].member? port) && ":#{port}" || ''
      queryHash = q
      queryHash.delete 'host'
      queryString = queryHash.empty? ? '' : (HTTP.qs queryHash)
      # origin URI
      urlHTTPS = scheme && scheme=='https' && uri || ('https://' + host + portNum + path + formatSuffix + queryString)
      urlHTTP  = 'http://'  + host + portNum + (path||'/') + formatSuffix + queryString
      # local URI
      cache = ('/' + host + (if FlatMap.member?(host) || (qs && !qs.empty?) # mint a path
                             hash = ((path||'/') + qs).sha2          # hash origin path
                             type = useExtension ? ext : 'cache' # append suffix
                             '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # plunk in semi-balanced bins
                            else # preserve upstream path
                              name = path[-1] == '/' ? path[0..-2] : path # strip trailing-slash
                              name + (useExtension ? '' : '.cache') # append suffix
                             end)).R env
      cacheMeta = cache.metafile

      # lazy updater, called by need
      updates = []
      update = -> url {
        begin # block to catch 304-response "error"
#          puts "fetch #{url}"
          open(url, head) do |response| # response

            if @r # HTTP-request calling context - preserve origin bits
              @r[:Response]['Access-Control-Allow-Origin'] ||= '*'
              response.meta['set-cookie'].do{|cookie| @r[:Response]['Set-Cookie'] = cookie}
            end

             # index updates
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # cache body
              mime = response.meta['content-type'].do{|type| type.split(';')[0] } || ''
              cacheMeta.writeFile [mime, url, ''].join "\n" unless useExtension
              # index content
              updates.concat(case mime
                             when /^application\/atom/
                               cache.indexFeed
                             when /^application\/rss/
                               cache.indexFeed
                             when /^application\/xml/
                               cache.indexFeed
                             when /^text\/html/
                               if feedURL? # HTML typetag on specified feed URL
                                 cache.indexFeed
                               else
                                 cache.indexHTML host
                               end
                             when /^text\/xml/
                               cache.indexFeed
                             else
                               []
                             end || [])
            end
          end
        rescue OpenURI::HTTPError => e
          raise unless e.message.match? /304/
        end}

      # conditional update
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
        begin # prefer HTTPS w/ fallback HTTP attempt
          update[urlHTTPS]
        rescue
          update[urlHTTP]
        end
        cacheMeta.touch if cacheMeta.e # bump timestamp
      end

      # response
      if @r # HTTP calling context
        if cache.exist?
          # preserve upstream format?
          if UpstreamToggle[@r['SERVER_NAME']] || UpstreamFormat.member?(@r['SERVER_NAME']) || cache.noTransform?
            cache.fileResponse
          else # transformable
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script/shell caller
        updates.empty? ? self : updates
      end

    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts msg, trace
      @r ? [500, {'Content-Type' => 'text/html'},
            [htmlDocument({uri => {Content => [{_: :style, c: "body {background-color: red !important}"},
                                               {_: :h3, c: msg.hrefs}, {_: :pre, c: trace.hrefs},
                                               {_: :h4, c: 'request'},
                                               (HTML.kv (HTML.urifyHash head), @r), # request header
                                               ([{_: :h4, c: "response #{e.io.status[0]}"},
                                                (HTML.kv (HTML.urifyHash e.io.meta), @r), # response header
                                                (CGI.escapeHTML e.io.read.to_utf8)] if e.respond_to? :io) # response body
                                              ]}})]] : self
    end
    alias_method :GETthru, :remoteNode

    # toggle upstream-UI preference on
    PathGET['/go-direct'] = -> r {
      r.q['u'].do{|u|
        UpstreamToggle[u.R.host] = true; [302, {'Location' => u}, []]
      } || r.notfound }

    # toggle upstream-UI preference off
    PathGET['/go-indirect'] = -> r {
      r.q['u'].do{|u|
        UpstreamToggle.delete u.R.host; [302, {'Location' => u}, []]
      } || r.notfound }

    PathGET['/cache'] = -> cache {
      cache.q['url'].do{|url|
        r = url.R cache.env
        if r.host == 'bit.ly'
          r.cachedRedirect
        elsif %w{png jpg webp}.member? r.ext
          ('//' + r.host + r.path).R(cache.env).remoteNode
        else
          r.remoteNode
        end
      } || [200, {'Content-Type' => 'text/html'}, ['<form method="GET"><input name="url" autofocus></form>']] }

    PathGET['/generate_204'] = -> _ {Response_204}

    # Discourse
    PathGET['/clicks/track'] = -> r {[302,{'Location' => r.q['url']},[]]}

    # DuckDuckGo
    ['',0,1,2,3,4].map{|n|
      HostGET['proxy'+n.to_s+'.duckduckgo.com'] = -> re {
        case re.parts[0]
        when 'iu'
          [302,{'Location' => re.q['u'],
                'Access-Control-Allow-Origin' => '*'
               },[]]
        when 'iur'
          [302,{'Location' => re.q['image_host']},[]]
        when 'ip3'
          re.ext == 'ico' ? re.favicon : re.notfound
        when 'mapboxapi'
          re.remoteNode
        when 'mapkit'
          original = re.env['QUERY_STRING'].R re.env
          original.env['QUERY_STRING'] = original.query
          original.remoteNode
        else
          re.notfound
        end}}

    # eBay
    HostGET['rover.ebay.com'] = -> r {
      if r.parts[0] == 'rover'
        [302, {'Location' => r.q['mpre']}, []]
      else
        r.deny
      end
    }

    # Embedly
    HostGET['i.embed.ly'] = -> r {
      if r.path == '/1/display/resize'
        [302, {'Location' => r.q['url']}, []]
      else
        r.deny
      end
    }

    # Google
    %w{mail news}.map{|_| "//#{_}.google.com".R.HTTPthru}
    %w{feedproxy.google.com gmail.com google.com}.map{|h| HostGET[h] = -> r {r.cachedRedirect}}

    HostGET['www.google.com'] = -> r {
      case r.parts[0]
      when nil
        [200, {'Content-Type' => 'text/html'}, ['<form method="GET" action="/search"><input name="q" autofocus></form>']]
      when 'gmail'
        r.cachedRedirect
      when /^im(ages?|gres)|logos|maps|search$/
        r.remoteNode
      when 'url'
        [302, {'Location' => ( r.q['q'] || r.q['url'] )}, []]
      else
        r.deny
      end}

    # IG
    HostGET['instagram.com'] = -> r {[302, {'Location' =>  "https://www.instagram.com" + r.path},[]]}
    HostGET['l.instagram.com'] = -> r {[302,{'Location' => r.q['u']},[]]}
    HostGET['www.instagram.com'] = -> r {r.remoteNode}

    # Imgur
    HostGET['imgur.com'] = HostGET['i.imgur.com'] = -> re {
      if !re.ext.empty? # file extension
        if 'i.imgur.com' == re.host # image host
          re.remoteNode # cached image
        else # redirect to image host
          [301,{'Location' => 'https://i.imgur.com' + re.path},[]]
        end
      else # redirect to image file
        UnwrapImage[re]
      end}

    # Mixcloud
    HostPOST['www.mixcloud.com'] = -> r {
      r.path == '/graphql' ? r.POSTthru : r.trackPOST
    }

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {
      if r.path == '/success.txt'
        [200, {'Content-Type' => 'text/plain'},["success\n"]]
      else
        r.deny
      end}

    # Reddit
    HostGET['i.reddit.com'] = HostGET['np.reddit.com'] = HostGET['reddit.com'] = -> re {[302,{'Location' => 'https://www.reddit.com' + re.path + re.qs},[]]}

    # Souncloud
    HostGET['exit.sc'] = -> r {[302,{'Location' => r.q['url']},[]]}

    # YouTube
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode
        [200, {'Content-Type' => 'text/html'},['<form method="GET" action="/results"><input name="q" autofocus></form>']]
      elsif %w{browse_ajax c channel embed feed get_video_info heartbeat iframe_api live_chat playlist user results signin watch watch_videos yts}.member? mode
        r.remoteNode
      elsif mode == 'redirect'
        [302, {'Location' =>  r.q['q']},[]]
      elsif mode.match? /204$/
        Response_204
      else
        r.deny
      end}
    HostGET['youtube.com'] = HostGET['m.youtube.com'] = -> r {[302, {'Location' =>  "https://www.youtube.com" + r.path + r.qs},[]]}
    HostGET['youtu.be'] = HostGET['y2u.be'] = -> re {[302,{'Location' => 'https://www.youtube.com/watch?v=' + re.path[1..-1]},[]]}

    # T-Mobile
    HostGET['lookup.t-mobile.com'] = -> re {[200, {'Content-Type' => 'text/html'}, [re.htmlDocument({re.uri => {'dest' => re.q['origurl'].R}})]]}

    # Twitter
    HostGET['mobile.twitter.com'] = HostGET['www.twitter.com'] = -> r {[302, {'Location' =>  "https://twitter.com" + r.path},[]]}
    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter,
                             Link => []}}

        ConfDir.join('twitter.com.bu').R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}

        [200,{'Content-Type' => 'text/html'},[re.htmlDocument(graph)]]
      else
        re.remoteNode
      end}

  end
end
