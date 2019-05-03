class WebResource
  module HTTP

    # Cloudflare
    HostGET['cdnjs.cloudflare.com'] = -> r {r.remoteNode} # bypass JS filtering for this host

    # Facebook
    HostGET['www.facebook.com'] = -> z {
      if %w{ajax api connect plugins si tr}.member?(z.parts[0]) || z.path.match?(/reaction/) || z.ext == 'php'
        z.deny
      else
        z.remoteNode
      end}
    HostGET['l.facebook.com']  = -> r {[301, {'Location' => r.q['u']},  []]}
    HostGET['l.instagram.com'] = -> r {[301, {'Location' => r.q['u']},  []]}

    # Google
    HostGET['www.google.com'] = -> r {[nil,*%w{aclk async images imghp imgres maps recaptcha search searchbyimage js webhp xjs}].member?(r.parts[0]) ? r.remote : r.deny}

    # Mozilla
    HostGET['detectportal.firefox.com'] = -> r {[200, {'Content-Type' => 'text/plain'}, ["success\n"]]}

    # Twitter
    HostGET['t.co'] = -> r {
      if %w{i}.member? r.parts[0]
        r.deny
      else
        r.remoteNode
      end}
    HostGET['twitter.com'] = -> re {
      if re.path == '/'
        graph = {Twitter => {'uri' => Twitter, Link => []}}
        '/twitter'.R.lines.shuffle.each_slice(16){|s|
          graph[Twitter][Link].push (Twitter+'/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u.chomp}.intersperse('+OR+').join).R}
        [200, {'Content-Type' => 'text/html'}, [re.htmlDocument(graph)]]
      else
        re.remoteNode
      end}

    # YouTube
    HostGET['www.youtube.com'] = -> r {
      mode = r.parts[0]
      if !mode || %w{browse_ajax c channel embed feed get_video_info guide_ajax heartbeat iframe_api live_chat playlist user results signin watch watch_videos yts}.member?(mode)
        r.remoteNode
      elsif mode == 'redirect'
        [301, {'Location' =>  r.q['q']},[]]
      elsif mode.match? /204$/
        [204, {'Content-Length' => 0}, []]
      else
        r.drop
      end}

  end
  module Webize

    # Twitter
    def tweets
      Nokogiri::HTML.parse(readFile).css('div.tweet').map{|tweet|
        s = Twitter + tweet.css('.js-permalink').attr('href')
        authorName = tweet.css('.username b')[0].inner_text
        author = (Twitter + '/' + authorName).R
        ts = Time.at(tweet.css('[data-time]')[0].attr('data-time').to_i).iso8601
        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, Twitter.R
        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'tweetedlink'+rand.to_s.sha2)
            a.set_attribute('href', Twitter + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
        end
        tweet.css('img').map{|img|
          yield s, Image, img.attr('src').to_s.R}}
    end
    TriplrHTML['twitter.com'] = :tweets
    IndexHTML['twitter.com'] = -> page { graph = {}; posts = []
      # collect triples
      page.tweets{|s,p,o|
        graph[s] ||= {'uri'=>s}
        graph[s][p] ||= []
        graph[s][p].push o}
      # link to timeline
      graph.map{|u,r|
        r[Date].do{|t|
          # mint timeline-entry identifier
          slug = (u.sub(/https?/,'.').gsub(/\W/,'.')).gsub /\.+/,'.'
          time = t[0].to_s.gsub(/[-T]/,'/').sub(':','/').sub /(.00.00|Z)$/, ''
          doc = "/#{time}#{slug}.e".R
          # store tweet
          if !doc.e
            doc.writeFile({u => r}.to_json)
            posts << doc
          end}}
      posts} # indexed tweets

  end
end
