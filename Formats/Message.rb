# coding: utf-8
class WebResource
  module HTML

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
          grouped = posts.size != 1
          color = env[:colors][to.R.display_name] ||= (grouped ? ('#%06x' % (rand 16777216)) : '#444')
          {style: "background: repeating-linear-gradient(-45deg, #000, #000 .875em, #{color} .875em, #{color} 1em); #{grouped ? 'padding: .42em' : ''}",
           c: posts.sort_by!{|r|(r[Content] || r[Image] || [0])[0].size}.map{|post| Markup[Post][post,env]}}}
      end}

    Markup[Post] = -> post, env {
      post.delete Type
      uri = post.delete('uri') || ('#' + Digest::SHA2.hexdigest(rand.to_s))
      resource = uri.R env
      authors = post.delete(Creator) || []
      date = (post.delete(Date) || [])[0]
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
      hasPointer = false
      local_id = if !resource.path || (resource.host == env[:base].host && resource.path == env[:base].path)
                   resource.fragment
                 else
                   uri_hash
                 end
      if authors.find{|a| KillFile.member? a.to_s}
        authors.map{|a| CGI.escapeHTML a.R.display_name if a.respond_to? :R}
      else
        {class: resource.deny? ? 'blocked post' : :post,
         c: ["\n",
             (post.delete(Title)||[]).map(&:to_s).map(&:strip).compact.-([""]).uniq.map{|title|
               title = title.to_s.sub(/\/u\/\S+ on /,'')
               unless env[:title] == title
                 env[:title] = title
                 hasPointer = true
                 [{_: :a,  id: local_id, class: :title,
                   href: resource.href, c: [(post.delete(Schema+'icon')||[]).map{|i|{_: :img, src: i.href}},CGI.escapeHTML(title)]}, " \n"]
               end},
             {class: :pointer,
              c: [({_: :a, class: :date, href: 'http://localhost:8000/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date), ' ',
                  ({_: :a, c: '☚', href: resource.href, id: local_id} unless hasPointer)]},
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
