# coding: utf-8
class WebResource

  module HTML

    # RDF -> (tabular) Markup

    # resource -> (colA: key, colB: val) table
    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.display_name,
            c: ["\n",
                {_: :td, class: 'k',
                 c: Markup[Type][type, env]}, "\n",
                {_: :td, class: 'v',
                 c: k==Link ? MarkupGroup[Link][vs, env] : vs.map{|v|markup k, v, env}}]}, "\n"] unless k == 'uri' && vs[0] && vs[0].to_s.match?(/^_:/))}} # hide bnode internal-identifiers
    end

    # graph -> ( property -> column, resource -> row) table
    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      qs = env[:base].query_values || {}
      keys = graph.select{|r|r.respond_to? :keys}.map{|r|r.keys}.flatten.uniq - [Abstract, Content, DC+'identifier', Image, Video, SIOC+'richContent', Title] # fields in main column
      keys = [Creator, *(keys - [Creator])] if keys.member? Creator

      if env[:sort]
        ascending = qs['order'] == 'asc'
        attr = env[:sort]
        attr = Date if %w(date new).member? attr
        attr = Content if attr == 'content'
        sortable, unsorted = graph.partition{|r|r.has_key? attr}
        sorted = sortable.sort_by{|r|r[attr]}
        sorted.reverse! unless ascending
        graph = [*sorted, *unsorted]
      end

      {_: :table, class: :tabular,                    # table
       c: [{_: :thead,
            c: {_: :tr, c: keys.map{|p|               # table header
                  p = p.R; slug = p.display_name
                  icon = Icons[p.uri] || slug
                  [{_: :th,
                    c: {_: :a, id: 'sort_by_' + slug, href: HTTP.qs(qs.merge({'sort' => p.uri, 'order' => ascending ? 'desc' : 'asc'})), c: icon}}, "\n"]}}}, "\n", # pointer to sorted column
           {_: :tbody,
            c: graph.map{|resource|
              re = (resource['uri'] || ('#'+Digest::SHA2.hexdigest(rand.to_s))).to_s.R env                   # resource identifier
              local_id = re.path == env[:base].path && re.fragment || ('r' + Digest::SHA2.hexdigest(re.uri)) # table-row identifier
              [{_: :tr, id: local_id, c: keys.map{|k| # row
                 [{_: :td, class: re.deny? ? 'blocked' :  '', property: k,
                  c: if k == 'uri'                                                                           # main column
                   tCount = 0
                   [(resource[Title]||[]).map{|title|
                      title = title.to_s.sub(/\/u\/\S+ on /, '').sub /^Re: /, ''                             # clean title
                      unless env[:title] == title                                                            # omit title if repeated on subsequent resource
                        env[:title] = title; tCount += 1
                        [{_: :a,href: re.href,class: :title,type: :node,c: CGI.escapeHTML(title),id: 'r'+Digest::SHA2.hexdigest(rand.to_s)}, ' '] # title
                      end},
                    ({_: :a,href: re.href,class: :id,type: :node,c: '☛',id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} if tCount == 0),    # resource pointer
                    ({class: :abstract, c: resource[Abstract]} if resource.has_key? Abstract),                                           # abstract
                    [Image, Video].map{|t|(resource[t]||[]).map{|i|Markup[t][i,env]}},                                                   # image & video links
                    ([resource[Content], resource[SIOC+'richContent']] unless (resource[Creator]||[]).find{|a|KillFile.member? a.to_s})] # HTML content
                  else
                    if Type == k && resource.has_key?(Type) && [Audio.R, Video.R].member?(resource[Type][0])                             # play-button on A/V types
                      playerType = resource[Type][0] == Audio.R ?  'audio' : 'video'
                      {_: :a, href: '#', c: '▶️', onclick: 'var player = document.getElementById("' + playerType + '"); player.src="' + re.href + '"; player.play()'}
                    else
                      (resource[k]||[]).yield_self{|r|r.class == Array ? r : [r]}.map{|v| markup k, v, env }                             # type represented as icon or shortname
                    end
                   end}, "\n" ]}}, "\n" ]}}]}
    end

    Markup[List] = -> list, env {
      tabular((list[Schema+'itemListElement'] || list[Schema+'ListItem'] || list['https://schema.org/itemListElement']||[]).map{|l|
                l.respond_to?(:uri) && env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri, Title => [l.uri]} : l)}, env)}

  end

end
