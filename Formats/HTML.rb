# coding: utf-8
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
    StripAttrs = %w(bgcolor class height http-equiv layout ping role style tabindex target theme width)

    def self.clean body, base
      html = Nokogiri::HTML.fragment body

      # stripped elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{clickability counter.ru quantserve scorecardresearch}.map{|co| html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # images
      # CSS:background-image → <img>
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(/url\(['"]*([^\)'"]+)['"]*\)/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      # <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}
      # <div> → <img>
      html.css("div[class*='image'][data-src]").map{|div|
        div.add_child "<img src=\"#{div['data-src']}\">"}

      html.traverse{|e| # visit nodes
        e.attribute_nodes.map{|a| # visit attributes
          e.set_attribute 'src', a.value if LazySRC.member? a.name            # @src map
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name # @srcset
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || StripAttrs.member?(a.name)} # strip attrs

        if e['href']
          ref = e['href'].R
          e.add_child " <span class='uri'>#{CGI.escapeHTML e['href'].sub(/^https?:..(www.)?/,'')[0..127]}</span> " # show full(er) URL
          e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) unless e['id'] # identify node for traversal
          css = [:uri]; css.push :path if !ref.host || (ref.host == base.host)
          e['href'] = base.join e['href'] unless ref.host                               # resolve relative references
          e['class'] = css.join ' '                                                     # node CSS-class for styling
        elsif e['id']                                                                   # identified node w/ no target link
          e.set_attribute 'class', 'identified'                                         # node CSS-class for styling
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id']}</span> " # add link to target
        end

        e['src'] = base.join e['src'] if e['src'] && !e['src'].R.host}                  # resolve image locations

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

    def self.webizeHash hash, &y
      yield hash if block_given?
      webized = {}
      hash.map{|key, value|
        webized[key] = webizeValue value, &y}
      webized
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

      GlobalGunk = %w{
        [class*='cookie']  [id*='cookie']
        [class*='related'] [id*='related']
        [class*='share']   [id*='share']
        [class*='social']  [id*='social']
        [class*='topbar']  [id*='topbar']
        [class^='promo']   [id^='promo']  [class^='Promo']  [id^='Promo']
footer  [class^='footer']  [id^='footer']
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
        if hostTriplr = Triplr[@base.host] ||
                        Triplr[@base.respond_to?(:env) && @base.env && @base.env[:query] && @base.env[:query]['host']]
          @base.send hostTriplr, n, &f
        end

        # embedded RDF in RDFa and JSON-LD
        unless @opts[:noRDF]
          embeds = RDF::Graph.new
          # JSON-LD
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"

          # RDFa
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"

          # emit triples
          embeds.each_triple{|s,p,o|
            p = MetaMap[p.to_s] || p # predicate map
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # show unresolved property-names
            yield s, p, o unless p == :drop}
        end

        # <link>
        n.css('head link[rel]').map{|m|
          if k = m.attr("rel") # predicate
            if v = m.attr("href") # object
              @base.env[:links][:prev] ||= v if k=='prev'
              @base.env[:links][:next] ||= v if k=='next'
              @base.env[:links][:feed] ||= v if k=='alternate' && v.R.path&.match?(/^\/feed\/?$/)
              k = MetaMap[k] || k
              puts [k, v].join "\t" unless k.to_s.match? /^(drop|http)/
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
          [*GlobalGunk, *SiteGunk[@base.host]].map{|s| # strip elements
            #body.css(s).map{|c| puts "🛑 "+s, c, "\n"*3}
            body.css(s).map &:remove}
          yield subject, Content, HTML.clean(body.inner_html, @base).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        else # <body> missing, emit doc - <head>
          puts "WARNING missing <body> in #{@base}"
          n.css('head').remove
          yield subject, Content, HTML.clean(n.inner_html, @base).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        end
      end
    end
  end
end

class WebResource
  module HTML

    def chrono_sort
      env[:query].update 'sort' => 'date',
                         'view' => 'table'
    end

    def self.colorize color = '#%06x' % (rand 16777216)
      "color: black; background-color: #{color}; border-color: #{color}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph=nil
      graph ||= treeFromGraph
      env[:images] ||= {}
      env[:colors] ||= {}
      titleRes = [ # title resource
        '', path,
        host && path && ('//' + host + path),
        host && path && ('https://' + host + path),
      ].compact.find{|u| graph[u] && graph[u][Title]}
      bc = '/' # breadcrumb path
      icon = ('//' + (host || 'localhost') + '/favicon.ico').R # site icon
      link = -> key, content { # render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url, id: key, class: :icon, c: content},
           "\n"]
        end}
      htmlGrep if env[:graph] && env[:grep]

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS, ".idlink, .identified {", HTML.colorize, '}']}, "\n",
                             (env[:links] || {}).map{|type,uri|
                               {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ]}, "\n",
                        {_: :body,
                         c: [{class: :toolbox,
                              c: [(icon.fsPath.exist? && icon.fsPath.node.size != 0) ? {_: :a, href: '/', id: :host, c: {_: :img, src: icon.uri}} : hostname.split('.').-(%w(com net org www)).reverse.map{|h| {_: :a, class: :breadcrumb, href: '/', c: h}},
                                 ({_: :a, id: :UX, class: :icon, style: 'color: #555', c: '⚗️', href: HTTP.qs((env[:query]||{}).merge({'UX' => 'upstream'}))} unless local?),
                                 ({_: :a, id: :tabular, class: :icon, style: 'color: #555', c: '↨',
                                    href: HTTP.qs((env[:query]||{}).merge({'view' => 'table', 'sort' => 'date'}))} unless env[:query] && env[:query]['view']=='table'),
                                  base.dir.parts.map{|p|
                                    [{_: :a, class: :breadcrumb, href: bc += p + '/', c: (CGI.escapeHTML URI.unescape p),
                                      id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}, ' ']},
                                  {_: :a, class: 'basename breadcrumb', href: path, c: (CGI.escapeHTML URI.unescape base.basename)},
                                  link[:media, '🖼️'], link[:feed, FeedIcon], link[:time, '🕒'],
                                 ]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash env), env
                             elsif env[:query] && env[:query]['view']=='table'
                               HTML.tabular graph, env
                             else
                               HTML.tree Treeize[graph], env
                             end,
                             link[:down,'&#9660;'],
                             {_: :script, c: ["\n", SiteJS]}, "\n"
                            ]}]}]
    end

    def htmlGrep
      graph = env[:graph]
      q = env[:query]['Q'] || env[:query]['q']
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
        render [{_: :a, href: x.uri, c: (%w{gif ico jpeg jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML((x.query || (x.basename && x.basename != '/' && x.basename) || (x.path && x.path != '/' && x.path) || x.host || x.to_s)[0..48]))}, ' ']
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
      keys = graph.select{|r|r.respond_to? :keys}.map{|r|r.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Link, Video, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
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
             {_: :tr, c: keys.map{|k|
                {_: :td,
                 c: if k == 'uri'
                  tCount = 0
                  [(resource[Title]||[]).map{|title|
                     title = title.to_s.sub(/\/u\/\S+ on /, '').sub /^Re: /, ''
                     unless env[:title] == title # show topic if changed from prior post
                       env[:title] = title; tCount += 1
                       {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: 'title', type: 'node', c: CGI.escapeHTML(title)}
                     end},
                   ({_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: 'id', type: 'node', c: '&#x1f517;'} if tCount == 0),
                   resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                   [Image, Video].map{|t|(resource[t]||[]).map{|i| Markup[t][i,env]}},
                   resource[Content],
                   (resource[Link]||[]).map{|i| Markup[Link][i,env]}]
                else
                  (resource[k]||[]).map{|v|value k, v, env }
                 end}}}}]}
    end

    # Hash -> Markup
    def self.tree t, env, name=nil
      url = t[:RDF]['uri'] if t[:RDF]
      css = {style: "border: .08em solid #{'#%06x' % rand(16777216)}"} if name && t.keys.size > 1
      ["\n",
       {class: :tree,
        c: [(["\n",{_: :a, href: url, c: CGI.escapeHTML(name.to_s[0..85])},"\n"] if name && url),
            t.map{|_name, _t|
              _name == :RDF ? (value nil, _t, env) : (tree _t, env, _name)}]}.update(css ? css : {})]
    end

    # RDF::Graph -> URI-indexed Hash
    def treeFromGraph
      return {} unless env[:repository]
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
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || t.basename}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Date] = -> date, env=nil {{_: :a, class: :date, c: date, href: '/' + date[0..13].gsub(/[-T:]/,'/')}}

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
      cssname = 'post'
      cssname += ' main' if uri.R.path == env['REQUEST_PATH']
      identified = false
      {class: cssname,
       c: ["\n",
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               [{_: :a, class: 'title', type: 'node', href: uri, c: CGI.escapeHTML(title)}.update(identified ? {} : (identified = true; {id: uri_hash})), " \n"]
             end},
           abstracts,
           ({_: :a, id: uri_hash, class: 'id', type: :node, c: '☚', href: uri} if uri && !identified), "\n", # minimum pointer
           ([{_: :a, class: :date, id: 'date' + uri_hash, href: '/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date}, "\n"] if date && uri_hash),
           images.map{|i| Markup[Image][i,env]},
           {_: :table, style: 'border-spacing: 0',
            c: {_: :tr,
                c: [{_: :td, style: 'padding: 0',
                     c: from.map{|f|Markup[Creator][f,env]},
                     class: :from}, "\n",
                    {_: :td, c: '&rarr;'},
                    {_: :td, style: 'padding: 0',
                     c: [to.map{|f|Markup[To][f,env]},
                         post.delete(SIOC+'reply_of')],
                     class: :to}, "\n"]}}, "\n",
           content, (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}}

    Markup[List] = -> list, env {
      {class: :list,
       c: tabular((list[Schema+'itemListElement']||list[Schema+'ListItem']||
                   list['https://schema.org/itemListElement']||[]).map{|l|
                    l.respond_to?(:uri) && env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri,
                                                                                             Title => [l.uri]} : l)}, env)}}

    Markup[Title] = -> title, env {
      if title.class == String
        {_: :h3, class: :title, c: CGI.escapeHTML(title)}
      end}

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
