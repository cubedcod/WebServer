class WebResource
  module HTTP

    # Hosts with OPTIONS/POST/PUT capability
    POSThosts = /(\.(edu|gov)|(anvato|api\.(brightcove|twitter)|(android.*|clients?[0-9]?|drive|groups|images|mail|www)\.google|android.googleapis|mirrors.lolinent|reddit|soundcloud|youtube|talk.zerohedge|zillow)\.(com|net))$/

    # original-host user-interface preference
    UI = {
      's.ytimg.com' => true,
      'www.youtube.com' => true,
    }

    # Facebook
    HostGET['l.facebook.com']  = -> r {[301, {'Location' => r.q['u']},  []]}
    HostGET['l.instagram.com'] = -> r {[301, {'Location' => r.q['u']},  []]}
    HostGET['s.yimg.com'] = -> r {r.fetch}

    HostGET['twitter.com'] = -> r {
      if r.path == '/'
        sources = r.subscriptions.shuffle.each_slice(16){|s| Twitter + '/search?f=tweets&vertical=default&q=' + s.map{|u| 'from:' + u}.intersperse('+OR+').join } # source URI
        [200, {'Content-Type' => 'text/html'}, [re.htmlDocument({Twitter => {'uri' => Twitter, Link => sources}})]]
      elsif r.path == '/new'
        
      else
        r.remote
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
