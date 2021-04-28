# coding: utf-8
class WebResource
  module HTML

    # RDF from message-board post
    def Chan doc
      doc.css('.post, .postCell, .post-container').map{|post|
        num = post.css('a.linkSelf, a.post_no, .postNum a')[0]                # post identifier
        subject = join(num ? num['href'] : ('#' + (post['data-post-no'] || post['id'] || (Digest::SHA2.hexdigest post.to_s))))
        graph = ['https://', subject.host, subject.path.sub(/\.html$/, ''), '/', subject.fragment].join.R

        yield subject, Type, Post.R, graph                                    # post typetag

        post.css('time, .dateTime').map{|date|                                # timestamp from unixtime
          yield subject, Date, (date['datetime'] || Time.at((date['data-utc'] || date['unixtime']).to_i).iso8601), graph }

        post.css('.labelCreated').map{|created|                               # freeform timestamp
          yield subject, Date, Chronic.parse(created.inner_text).iso8601, graph}

        post.css('.name, .post_author, .poster-name, .postername').map{|name| # author
          yield subject, Creator, name.inner_text, graph }

        post.css('.post-subject, .post_title, .subject, .title').map{|subj|   # title
          yield subject, Title, subj.inner_text, graph }

        post.css('.file-image, .fileThumb, .imgLink').map{|a|                 # image references
          yield subject, Image, (join a['href']), graph if a['href'] }

        post.css('.post_image, .post-image, img.thumb').map{|img|             # images
          yield subject, Image, (join img.parent['href']), graph }

        post.css('img.multithumb, img.multithumbfirst').map{|img|             # image thumbnails
          yield subject, Image, (join img.parent.parent['href']), graph }

        post.css('[href$="m4v"], [href$="mp4"], [href$="webm"]').map{|a|      # videos
          yield subject, Video, (join a['href']), graph }

        post.css('.body, .divMessage, .message, .post-body, .postMessage, .text').map{|msg|
          msg.css('a[class^="ref"], a[onclick*="Reply"], .post-link, .quotelink, .quoteLink').map{|reply_of|
            yield subject, To, (join reply_of['href']), graph                 # reply-of references
            reply_of.remove}

          msg.traverse{|n|                                                    # references in text content
            if n.text? && n.to_s.match?(/https?:\/\//)
              n.add_next_sibling n.to_s.hrefs
              n.remove
            end}

          yield subject, Content, msg, graph }                                # message body

        post.remove }

      doc.css('#boardNavMobile, #delform, #absbot, #navtopright, #postForm, #postingForm, #actionsForm, #thread-interactions').map &:remove
    end

    Markup[DC+'language'] = -> lang, env {
      {'de' => '🇩🇪',
       'en' => '🇬🇧',
       'fr' => '🇫🇷',
       'ja' => '🇯🇵',
      }[lang] || lang}

    Markup[Title] = -> title, env {
      if title.class == String
        [{_: :span, class: :title, c: CGI.escapeHTML(title)}, ' ']
      end}

    Markup[Creator] = Markup[To] = Markup['http://xmlns.com/foaf/0.1/maker'] = -> creator, env {
      if creator.class == String || !creator.respond_to?(:R)
        CGI.escapeHTML creator.to_s
      else
        uri = creator.R env
        name = uri.display_name
        color = env[:colors][name] ||= '#%06x' % (rand 16777216)
        {_: :a, href: uri.href, class: :fromto, style: "background-color: #{color}; color: black", c: name}
      end}

    MarkupGroup[Post] = -> posts, env {
      if env[:view] == 'table'
        HTML.tabular posts, env
      else
        posts.group_by{|p|(p[To] || [''.R])[0]}.map{|to, posts|
          color = env[:colors][to.R.display_name] ||= (posts.size != 1 ? ('#%06x' % (rand 16777216)) : '#444')
          {class: :posts, style: "border-color: #{color}",
           c: posts.sort_by!{|r|(r[Content] || r[Image] || [0])[0].size}.map{|post| Markup[Post][post,env]}}}
      end}

    Markup[Post] = -> post, env {
      post.delete Type
      resource = (post.delete('uri') || ('#' + Digest::SHA2.hexdigest(rand.to_s))).R env
      authors = post.delete(Creator) || []
      date = (post.delete(Date) || [])[0]
      id = 'r' + Digest::SHA2.hexdigest(resource.uri) # local identifier for nonlocal-resource representation
      hasPointer = false
      if authors.find{|a| KillFile.member? a.to_s}
        authors.map{|a| CGI.escapeHTML a.R.display_name if a.respond_to? :R}
      else
        {class: resource.deny? ? 'blocked post' : :post, id: env[:base].uri == resource.uri.split('#')[0] ? resource.fragment : id,
         c: ["\n",
             (post.delete(Title)||[]).map(&:to_s).map(&:strip).compact.-([""]).uniq.map{|title|
               title = title.to_s.sub(/\/u\/\S+ on /,'')
               unless env[:title] == title
                 env[:title] = title
                 hasPointer = true
                 [{_: :a, id: 't' + id, class: :title,
                   href: resource.href, c: [(post.delete(Schema+'icon')||[]).map{|i|{_: :img, src: i.href}},CGI.escapeHTML(title)]}, " \n"]
               end},
             {class: :pointer,
              c: [({_: :a, class: :date, href: 'http://localhost:8000/' + date[0..13].gsub(/[-T:]/,'/') + '#' + id, c: date} if date), ' ',
                  ({_: :a, c: '☚', href: resource.href, id: 'p' + id} unless hasPointer)]},
             {_: :table, class: :fromto,
              c: {_: :tr,
                  c: [{_: :td,
                       c: authors.map{|f|Markup[Creator][f,env]},
                       class: :from}, "\n",
                      {_: :td, c: '&rarr;'},
                      {_: :td,
                       c: [(post.delete(To)||[]).map{|f|Markup[To][f,env]},
                           post.delete(SIOC+'reply_of')],
                       class: :to}, "\n"]}},
             {class: :body,
              c: [({class: :abstract, c: post.delete(Abstract)} if post.has_key? Abstract),
                  {class: :content,
                   c: [(post.delete(Image) || []).map{|i| Markup[Image][i,env]},
                       ((env.has_key? :proxy_href) && (post.has_key? Content)) ? Webize::HTML.proxy_hrefs(post.delete(Content), env) : post.delete(Content),
                       post.delete(SIOC + 'richContent')]},
                  MarkupGroup[Link][post.delete(Link) || [], env],
                  (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}]}
      end}
  end
end
