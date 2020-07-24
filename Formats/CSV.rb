# coding: utf-8
class WebResource

  module HTML

    # Graph -> Markup

    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.select{|r|r.respond_to? :keys}.map{|r|r.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Link, Video, SIOC+'reply_of', SIOC+'richContent', SIOC+'user_agent', Title]
      keys = [Creator, *(keys - [Creator])] if keys.member? Creator
      if env[:sort]
        attr = env[:sort]
        attr = Date if %w(date new).member? attr
        attr = Content if attr == 'content'
        graph = graph.sort_by{|r| (r[attr]||'').to_s}.reverse
      end

      {_: :table, class: :tabular,
       c: [{_: :thead,
            c: {_: :tr, c: keys.map{|p|                                          # header
                  p = p.R
                  slug = p.fragment || (p.path && p.basename) || ' '
                  icon = Icons[p.uri] || slug
                  [{_: :th,
                    c: {_: :a, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}, "\n"]}}}, "\n", # sorting link
           {_: :tbody,
            c: graph.map{|resource|

              re = (resource['uri'] || ('#' + Digest::SHA2.hexdigest(rand.to_s))).R env                      # resource identity
              local_id = re.path == env[:base].path && re.fragment || ('r' + Digest::SHA2.hexdigest(re.uri)) # row identity

              [{_: :tr, id: local_id, c: keys.map{|k|                            # row
                 [{_: :td, property: k,
                  c: if k == 'uri'
                   tCount = 0
                   [(resource[Title]||[]).map{|title|
                      title = title.to_s.sub(/\/u\/\S+ on /, '').sub /^Re: /, ''
                      unless env[:title] == title
                        env[:title] = title; tCount += 1
                        {_: :a, href: re.href,                                   # link to row with title (changed from prior row)
                         class: :title,
                         type: :node,
                         c: CGI.escapeHTML(title), id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}
                      end},
                    ({_: :a, href: re.href,                                      # link to row
                      class: :id,
                      type: :node,
                      c: '🔗',
                      id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} if tCount == 0),
                    (resource[SIOC+'reply_of']||[]).map{|r|
                      {_: :a, href: r.to_s,
                       c: Icons[SIOC+'reply_of']} if r.class == RDF::URI || r.class == WebResource},
                    resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                    [Image,
                     Video].map{|t|(resource[t]||[]).map{|i|
                                         Markup[t][i,env]}},
                    (env[:cacherefs] ? [resource[Content],
                                        resource[SIOC+'richContent']].flatten.compact.map{|c|
                                         Webize::HTML.cacherefs c, env} : [resource[Content],
                                                                           resource[SIOC+'richContent']]).compact.join('<hr>'),
                    MarkupLinks[(resource[Link]||[]),env]]
                 else
                   (resource[k]||[]).map{|v|
                     markup k, v, env }
                   end}, "\n" ]}}, "\n" ]}}]}
    end

    Markup[List] = -> list, env {
      tabular((list[Schema+'itemListElement']||list[Schema+'ListItem']||
               list['https://schema.org/itemListElement']||[]).map{|l|
                l.respond_to?(:uri) && env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri, Title => [l.uri]} : l)}, env)}

  end

end
