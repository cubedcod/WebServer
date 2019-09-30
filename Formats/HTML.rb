# coding: utf-8
require 'nokogiri'
module Webize
  module HTML

    LazySRC = %w(
data-baseurl
data-delayed-url
data-hi-res-src
data-img-src
data-lazy-img
data-lazy-src
data-menuimg
data-native-src
data-original
data-src
image-src
)

    def self.clean body
      html = Nokogiri::HTML.fragment body

      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{clickability counter.ru quantserve scorecardresearch}.map{|co| html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # image elements
      # CSS:background-image → <img>
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      # <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}
      # <div> → <img>
      html.css("div[class*='image'][data-src]").map{|div|
        div.add_child "<img src=\"#{div['data-src']}\">"}

      html.traverse{|e|

        # local identifiers for links
        e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) if e['href'] && !e['id']

        # normalize src-attribute naming
        e.attribute_nodes.map{|a|
          e.set_attribute 'src', a.value if LazySRC.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name

          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height http-equiv layout ping role style tabindex target theme width}.member?(a.name)}}


      html.to_xhtml(:indent => 0)
    end

    def self.webizeValue v, &y
      case v.class.to_s
      when 'Hash'
        webizeHash v, &y
      when 'String'
        webizeString v, &y
      when 'Array'
        v.map{|_v| webizeValue _v, &y }
      else
        v
      end
    end

    def self.webizeHash h, &y
      u = {}
      if block_given?
        yield h if h['__typename'] || h['type']
      end
      h.map{|k,v|
        u[k] = webizeValue v, &y}
      u
    end

    def self.webizeString str, &y
      if str.match? /^(http|\/)\S+$/
        str.R
      else
        str
      end
    end

    class Format < RDF::Format
      content_type     'text/html', :extension => :html
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      BasicGunk = %w{
        [class*='cookie']  [id*='cookie']
        [class*='related'] [id*='related']
        [class*='share']   [id*='share']
        [class*='social']  [id*='social']
        [class*='topbar']  [id*='topbar']
        [class^='promo']   [id^='promo']  [class^='Promo']  [id^='Promo']
footer  [class^='footer']  [id^='footer']
header  [class^='header']  [id^='header'] [class*='Header'] [id*='Header']
nav     [class^='nav']     [id^='nav']
sidebar [class^='side']    [id^='side']
}

      def initialize(input = $stdin, options = {}, &block)
        @opts = options
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
        @base = options[:base_uri]
        @opts[:noRDF] = true if @base.to_s.match? /\/feed|polymer.*html/ # don't look for RDF in templates
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        scanContent{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      # HTML -> RDF
      def scanContent &f
        subject = @base         # subject URI
        n = Nokogiri::HTML.parse @doc # parse

        # host bindings
        if hostTriples = Triplr[@base.host] || Triplr[@base.respond_to?(:env) && @base.env && @base.env[:query] && @base.env[:query]['host']]
          @base.send hostTriples, n, &f
        end

        # embedded RDF in RDFa and JSON-LD
        unless @opts[:noRDF]
          embeds = RDF::Graph.new
          # JSON-LD
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"
          # RDFa
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"

          embeds.each_triple{|s,p,o|
            p = MetaMap[p.to_s] || p # predicate map
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/
            yield s, p, o unless p == :drop}
        end

        # <link>
        n.css('head link[rel]').map{|m|
          if k = m.attr("rel") # predicate
            if v = m.attr("href") # object
              @base.env[:links][:prev] ||= v if k=='prev'
              @base.env[:links][:next] ||= v if k=='next'
              k = MetaMap[k] || k
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield subject, k, v.R unless k == :drop
            end
          end}

        # <meta>
        n.css('head meta').map{|m|
          if k = (m.attr("name") || m.attr("property")) # predicate
            if v = m.attr("content")                    # object
              k = MetaMap[k] || k                       # normalize predicate
              case k
              when /lytics/
                k = :drop
              when 'https://twitter.com'
                v = ('https://twitter.com/' + v.sub(/^@/,'')).R
              when Abstract
                v = v.hrefs
              else
                v = HTML.webizeString v
                v = @base.join v if v.class == WebResource || v.class == RDF::URI
              end
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield subject, k, v unless k == :drop
            end
          end}

        # <title>
        n.css('title').map{|title| yield subject, Title, title.inner_text }

        # <video>
        ['video[src]', 'video > source[src]'].map{|vsel|
          n.css(vsel).map{|v|
            yield subject, Video, v.attr('src').R }}

        # <body>
        if body = n.css('body')[0]
          %w{content-body entry-content}.map{|bsel|
            if content = body.css('.' + bsel)[0]
              yield subject, Content, HTML.clean(content.inner_html)
            end}
          [*BasicGunk,*Gunk,*SiteGunk[@base.host]].map{|selector|
            body.css(selector).map{|sel|
              #puts "X"*80,"stripping #{selector}:", sel if ENV['VERBOSE']
              sel.remove }} # strip elements
          yield subject, Content, HTML.clean(body.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        else # body element missing
          n.css('head').remove
          yield subject, Content, HTML.clean(n.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        end
      end
    end
  end
end

class WebResource
  module HTML

    def self.colorize color = '#%06x' % (rand 16777216)
      "color: black; background-color: #{color}; border-color: #{color}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph = {}
      env[:images] ||= {}
      env[:colors] ||= {}
      titleRes = [ # title resource
        '', path,
        host && path && ('//' + host + path),
        host && path && ('https://' + host + path),
      ].compact.find{|u| graph[u] && graph[u][Title]}
      bc = '' # path breadcrumbs
      icon = ('//' + host + '/favicon.ico').R # site icon
      link = -> key, displayname { # render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url, id: key, class: :icon, c: displayname},
           "\n"]
          end}
      htmlGrep if env[:graph] && env[:grep]
 
      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                             ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n", {_: :script, c: ["\n", SiteJS]}, "\n",
                             (env[:links] || {}).map{|type,uri|
                               {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: [{class: :toolbox,
                              c: [{_: :a, id: :hostname, class: :hostname, href: '/',
                                   c: icon.cache.exist? ? {_: :img, src: icon.uri} : host},
                                  ({_: :a, id: :tabular, class: :icon, style: 'color: #555', c: '↨',
                                    href: HTTP.qs((env[:query]||{}).merge({'view' => 'table', 'sort' => 'date'}))} unless env[:query] && env[:query]['view']=='table'),
                                  parts.map{|p| [{_: :a, class: :breadcrumb, href: bc += '/' + p, c: p, id: 'r'+Digest::SHA2.hexdigest(rand.to_s)}, ' ']},
                                  #link[:up, '&#9650;'],
                                  ({_: :a, id: :UX, class: :icon, style: 'color: #555', c: '⚗️', href: HTTP.qs((env[:query]||{}).merge({'UX' => 'upstream'}))} unless local?)
                                 ]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash env), env
                             elsif env[:query] && env[:query]['view']=='table'
                               HTML.tabular graph, env
                             else
                               HTML.tree Treeize[graph], env
                             end, link[:down,'&#9660;']]}]}]
    end

    def htmlGrep
      graph = env[:graph]
      q = env[:query]['q']
      wordIndex = {}
      args = POSIX.splitArgs q
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      pattern = /(#{args.join '|'})/i

      # find matches
      graph.map{|k,v|
        graph.delete k unless (k.to_s.match pattern) || (v.to_s.match pattern)}

      # highlight matches in exerpt
      graph.values.map{|r|
        (r[Content]||r[Abstract]||[]).map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).yield_self{|lines|
          r[Abstract] = lines[0..5].map{|l|
            l.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g}) # wrap in styled node
            }} if lines.size > 0 }}

      # CSS
      graph['#abstracts'] = {Abstract => [HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})]}
    end

    # Hash -> Markup
    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || type.basename,
            c: ["\n",
                {_: :td, class: 'k', c: Markup[Type][type]}, "\n",
                {_: :td, class: 'v', c: vs.map{|v|
                   [(value k, v, env), ' ']}}]}, "\n"] unless k=='uri' && vs[0] && vs[0].to_s.match?(/^_:/))}}
    end

    # Markup -> HTML
    def self.render x
      case x
      when String
        x
      when Hash
        void = [:img, :input, :link, :meta].member? x[:_]
        '<' + (x[:_] || 'div').to_s +                        # open tag
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # child nodes
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close
      when Array
        x.map{|n|render n}.join
      when WebResource
        render [{_: :a, href: x.uri, id: 'l' + Digest::SHA2.hexdigest(rand.to_s), c: (%w{gif ico jpeg jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML((x.query || (x.basename && x.basename != '/' && x.basename) || (x.path && x.path != '/' && x.path) || x.host || x.to_s)[0..48]))}, ' ']
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end

    # Hash -> Markup
    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.select{|r|r.respond_to? :keys}.map{|r|r.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Video, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if %w(date new).member? attr
        attr = Content if attr == 'content'
        #attr = Title if attr == 'uri'
        graph = graph.sort_by{|r| (r[attr]||'').to_s}.reverse
      end
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p|
              p = p.R
              slug = p.fragment || p.basename
              icon = Icons[p.uri] || slug
              {_: :td, c: (env[:query]||{})['sort'] == p.uri ? icon : {_: :a, class: :head, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
           graph.map{|resource|
             has_content_row = [Abstract,Content,Image,Video].find{|k|resource.has_key? k}
             [{_: :tr, c: keys.map{|k|
                 {_: :td,
                  c: if k == 'uri'
                   tCount = 0
                   [(resource[Title]||[]).map{|title|
                      title = title.to_s.sub(/\/u\/\S+ on /, '').sub /^Re: /, ''
                      unless env[:title] == title # show topic if changed from prior post
                        env[:title] = title; tCount += 1
                        {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: 'title', type: 'node', c: CGI.escapeHTML(title)}
                      end},
                    ({_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: 'id', type: 'node', c: '&#x1f517;'} if tCount == 0)]
                 else
                   (resource[k]||[]).map{|v|value k, v, env }
                  end}}},
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                                (resource[Image]||[]).map{|i| {style: 'max-width: 28em', c: Markup[Image][i,env]}},
                                (resource[Video]||[]).map{|i| {style: 'max-width: 32em', c: Markup[Video][i,env]}},
                                resource[Content]]}} if has_content_row)]}]}
    end

    # Hash -> Markup
    def self.tree t, env, name=nil
      url = t[:RDF]['uri'] if t[:RDF]
      if name && t.keys.size > 1
        color = '#%06x' % rand(16777216)
        scale = rand(7) + 1
        position = scale * rand(960) / 960.0
        css = {style: "border: .08em solid #{color}; background: repeating-linear-gradient(#{rand 360}deg, #000, #000 #{position}em, #{color} #{position}em, #{color} #{scale}em)"}
      end
      ["\n",
       {class: :tree,
        c: [(["\n",{_: :a, href: url, c: CGI.escapeHTML(name.to_s[0..85])},"\n"] if name && url),
            t.map{|_name, _t|
              _name == :RDF ? (value nil, _t, env) : (tree _t, env, _name)}]}.update(css ? css : {})]
    end

    # Graph -> Hash
    def treeFromGraph
      tree = {}
      head = env && env[:query] && env[:query].has_key?('head')
      env[:repository].each_triple{|s,p,o| s = s.to_s;  p = p.to_s
        unless p == 'http://www.w3.org/1999/xhtml/vocab#role' || (head && p == Content)
          o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
          tree[s] ||= {'uri' => s}                      # subject
          tree[s][p] ||= []                             # predicate
          if tree[s][p].class == Array
            tree[s][p].push o unless tree[s][p].member? o # object
          else
            tree[s][p] = [tree[s][p],o] unless tree[s][p] == o
          end
        end}
      env[:graph] = tree
    end

    # Value -> Markup
    def self.value type, v, env
      if Abstract == type || Content == type # inlined HTML content
        v
      elsif Markup[type] # render-type given as argument
        Markup[type][v,env]
      elsif v.class == Hash        # resource (with data)
        types = (v[Type] || []).map{|t| MarkupMap[t.to_s] || t.to_s }
        shown = []
        [types.map{|type|
          if markup = Markup[type] # renderer found
            shown.push type        # mark as shown
            markup[v,env]          # show
          end},
         (unseen = types - shown ; puts "#{v['uri']} no renderers defined for: " + unseen.join(' ') unless unseen.empty?),
         (keyval v, env if shown.empty?)] # fallback renderer
      elsif v.class == WebResource # resource reference
        if %w{jpeg jpg JPG png PNG webp}.member? v.ext
          Markup[Image][v, env]    # image reference
        else
          v                        # generic reference
        end
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end

    # Hash -> Hash nested according to URI path
    Treeize = -> graph {
      tree = {}
      # visit nodes
      (graph.class == Array ? graph : graph.values).map{|node|
        re = (node['uri'] || '').R
        # traverse
        cursor = tree
        [re.host ? re.host.split('.').reverse : nil, re.parts, re.qs, re.fragment].flatten.compact.map{|name|
          cursor = cursor[name] ||= {}}
        if cursor[:RDF] # merge to existing node
          node.map{|k,v|
            unless k == 'uri'
              if cursor[:RDF][k]
                cursor[:RDF][k].concat v # merge value-lists
              else
                cursor[:RDF][k] = v # new key
              end
            end}
        else
          cursor[:RDF] = node # new node
        end}
      tree }

    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Type] = -> t, env=nil {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || t.basename}.update(Icons[t.uri] ? {} : {style: 'font-weight: bold'})
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Date] = -> date, env=nil {{_: :a, class: :date, href: '/' + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      [{_: :a,
        c: u.sub(/^https?.../,'')[0..79],
        href: u,
        id: 'l' + Digest::SHA2.hexdigest(rand.to_s),
        style: env[:colors][u.R.host] ||= HTML.colorize,
        title: u,
       },
       " \n"]}

    Markup[Creator] = Markup[To] = -> c, env {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R
        basename = u.basename
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        avatar = nil
        [{_: :a, href: u.to_s, id: 'a' + Digest::SHA2.hexdigest(rand.to_s),
          style: avatar ? '' : (env[:colors][name] ||= HTML.colorize),
          c: avatar ? {_: :img, class: :avatar, src: avatar} : name}.update(avatar ? {class: :avatar} : {}), ' ']
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post, env {
      post.delete Type
      uri = post.delete 'uri'
      titles = (post.delete(Title)||[]).map(&:to_s).map(&:strip).uniq
      abstracts = post.delete(Abstract) || []
      date = (post.delete(Date) || [])[0]
      from = post.delete(Creator) || []
      to = post.delete(To) || []
      images = post.delete(Image) || []
      content = post.delete(Content) || []
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri) if uri
      {class: :post,
       c: ["\n",
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               [{_: :a, id: 't' + Digest::SHA2.hexdigest(rand.to_s), class: 'title', type: 'node', href: uri, c: CGI.escapeHTML(title)}, " \n"]
             end},
           abstracts,
           {_: :a, class: 'id', c: '☚', href: uri}.update(titles.empty? ? {type: 'node'} : {}).update(uri ? {id: 'pt' + uri_hash} : {}), "\n",
           ([{_: :a, class: :date, id: 'date' + uri_hash, href: '/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date}, "\n"] if date && uri_hash),
           images.map{|i| Markup[Image][i,env]},
           {_: :table, class: :fromTo,
            c: {_: :tr,
                c: ["\n",
                    {_: :td,
                     c: from.map{|f|Markup[Creator][f,env]},
                     class: :from}, "\n",
                    {_: :td, c: '&rarr;'},
                    {_: :td,
                     c: [to.map{|f|Markup[To][f,env]},
                         post.delete(SIOC+'reply_of')],
                     class: :to}, "\n"]}}, "\n",
           content, (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}.update(uri ? {id: uri_hash} : {})}

    Markup[List] = -> list, env {
      {class: :list,
       c: tabular((list[Schema+'itemListElement']||list[Schema+'ListItem']||
                   list['https://schema.org/itemListElement']||[]).map{|l|
                    l.respond_to?(:uri) && env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri,
                                                                                             Title => [l.uri]} : l)}, env)}}

    Markup[LDP+'Container'] = -> dir , env {
      uri = dir.delete 'uri'
      [Type, Title, W3+'ns/posix/stat#mtime', W3+'ns/posix/stat#size'].map{|p|dir.delete p}
      {class: :container,
       c: [{_: :a, id: 'container' + Digest::SHA2.hexdigest(rand.to_s), class: :label, href: uri, type: :node, c: uri.R.basename}, '<br>',
           {class: :body, c: HTML.keyval(dir, env)}]}}

    Markup[Stat+'File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons[Stat+'File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

  end
end
