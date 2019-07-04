# coding: utf-8
module Webize
  module HTML
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
        [class*='message'] [id*='message']
        [class*='related'] [id*='related']
        [class*='share']   [id*='share']
        [class*='social']  [id*='social']
        [class*='topbar']  [id*='topbar']
        [class^='promo']   [id^='promo']  [class^='Promo']  [id^='Promo']
aside   [class*='aside']   [id*='aside']
footer  [class^='footer']  [id^='footer']
header  [class*='header']  [id*='header'] [class*='Header'] [id*='Header']
nav     [class^='nav']     [id^='nav']
sidebar [class^='side']    [id^='side']
}#.map{|sel| sel.sub /\]$/, ' i]'}
      #TODO see if Oga https://gitlab.com/yorickpeterse/oga et al support case-insensitive attribute selectors

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri]

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
                                      o.class == RDF::URI) ? o : (l = RDF::Literal (if [Abstract,Content].member? p
                                                                                    WebResource::HTML.clean o
                                                                                   else
                                                                                     o
                                                                                    end)
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      # HTML -> RDF
      def scanContent &f
        embeds = RDF::Graph.new # embedded graph-data
        subject = @base         # subject URI
        n = Nokogiri::HTML.parse @doc # parse doc

        # triplr host-binding
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, n, &f
        end

        # JSON-LD
        n.css('script[type="application/ld+json"]').map{|dataElement|
          begin
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)
          rescue
            puts "JSON-LD parse failed in #{@base}"
          end}

        # RDFa
        RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa parse failed in #{@base}"

        # embedded triples
        embeds.each_triple{|s,p,o|
          case p.to_s
          when 'http://purl.org/dc/terms/created'
            p = Date.R
          when 'content:encoded'
            p = Content.R
            o = o.to_s.hrefs
          end

          yield s, p, o}

        # <link>
        n.css('head link[rel]').map{|m|
          if k = m.attr("rel") # predicate
            if v = m.attr("href") # object
              k = {
                'alternate' => DC + 'hasFormat',
                'icon' => Image,
                'image_src' => Image,
                'apple-touch-icon' => Image,
                'apple-touch-icon-precomposed' => Image,
                'shortcut icon' => Image,
                'stylesheet' => :drop,
              }[k] || ('#' + k.gsub(' ','_'))
              yield subject, k, v.R unless k == :drop
            end
          end}

        # <meta>
        n.css('head meta').map{|m|
          if k = (m.attr("name") || m.attr("property")) # predicate
            if v = m.attr("content")                    # object

              # normalize predicates
              k = {
                'al:ios:url' => :drop,
                'apple-itunes-app' => :drop,
                'article:modified_time' => Date,
                'article:published_time' => Date,
                'description' => Abstract,
                'fb:admins' => :drop,
                'fb:pages' => :drop,
                'image' => Image,
                'msapplication-TileImage' => Image,
                'og:description' => Abstract,
                'og:image' => Image,
                'og:image:height' => Schema + 'height',
                'og:image:secure_url' => Image,
                'og:image:width' => Schema + 'width',
                'og:title' => Title,
                'sailthru.date' => Date,
                'sailthru.description' => Abstract,
                'sailthru.image.thumb' => Image,
                'sailthru.image.full' => Image,
                'sailthru.lead_image' => Image,
                'sailthru.secondary_image' => Image,
                'sailthru.title' => Title,
                'thumbnail' => Image,
                'twitter:creator' => 'https://twitter.com',
                'twitter:description' => Abstract,
                'twitter:image' => Image,
                'twitter:image:src' => Image,
                'twitter:site' => 'https://twitter.com',
                'twitter:title' => Title,
                'viewport' => :drop,
              }[k] || ('#' + k.gsub(' ','_'))

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
        unless (@base.host || '').match?(/(twitter).com/)
          if body = n.css('body')[0]
            %w{content-body entry-content}.map{|bsel|
              if content = body.css('.' + bsel)[0]
                yield subject, Content, HTML.clean(content.inner_html) rescue nil
              end}
            [*BasicGunk,*Gunk].map{|selector|
              body.css(selector).map{|sel|
                sel.remove }} # strip elements
            yield subject, Content, HTML.clean(body.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '') rescue nil
          else
            puts "no <body> found in HTML #{@base}"
            n.css('head').remove
            yield subject, Content, HTML.clean(n.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '') rescue nil
          end
        end
      end
    end
  end
end

class WebResource
  module HTML
    include URIs

    Icons = {
      'https://twitter.com' => '🐦',
      Abstract => '✍',
      Content => '✏',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      Date => '⌚',
      Image => '🖼',
      Link => '☛',
      SIOC + 'attachment' => '✉',
      SIOC + 'reply_of' => '↩',
      Schema + 'height' => '↕',
      Schema + 'width' => '↔',
      Video => '🎞',
      W3 + 'ns/ldp#contains' => '📁',
    }

    Markup = {}

    Treeize = -> graph {
      t = {}
      # visit nodes
      (graph.class==Array ? graph : graph.values).map{|node| re = node.R
        cursor = t  # cursor start
        # traverse
        [re.host ? re.host.split('.').reverse : nil, re.parts, re.qs, re.fragment].flatten.compact.map{|name|
          cursor = cursor[name] ||= {}}
        if cursor[:RDF] # merge to node
          node.map{|k,v|
            cursor[:RDF][k] = cursor[:RDF][k].justArray.concat v.justArray unless k == 'uri'}
        else
          cursor[:RDF] = node # insert node
        end}
      t } # tree

    SiteCSS = ConfDir.join('site.css').read
    SiteJS  = ConfDir.join('site.js').read

    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body
      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}
      # strip Javascript and tracking-images
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{quantserve scorecardresearch}.map{|co|
        html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # lift CSS background-image to image element
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}

      # traverse nodes
      html.traverse{|e|
        # assign link identifier
        e.set_attribute 'id', 'id'+rand.to_s.sha2 if e['href'] && !e['id']
        # traverse attribute nodes
        e.attribute_nodes.map{|a|
          # move nonstandard src attrs
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height layout ping role style tabindex target width}.member?(a.name)}}
      # unparse
      html.to_xhtml(:indent => 0)
    end

    def self.colorize bg = true
      "#{bg ? 'color' : 'background-color'}: black; #{bg ? 'background-' : ''}color: #{'#%06x' % (rand 16777216)}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph = {}

      # HEAD links
      @r ||= {}
      @r[:links] ||= {}
      @r[:images] ||= {}
      @r[:colors] ||= {}

      # title
      titleRes = [
        '#this', '',
        path && (path + '#this'), path,
        host && !path && ('//' + host + '#this'),
        host && !path && ('//' + host),
        host && path && ('https://' + host + path + '#this'),
        host && path && ('https://' + host + path),
        host && path && ('//' + host + path + '#this'),
        host && path && ('//' + host + path)
      ].compact.find{|u| graph[u] && !graph[u][Title].justArray.empty?}

      # render HEAD link as HTML
      link = -> key, displayname {
        if url = @r[:links][key]
          [url.R.data({id: key, label: displayname}),
           "\n"]
          end}


      htmlGrep graph, q['q'] if @r[:grep]
      subbed = subscribed?
      tabular = q['view'] == 'table'
      tabularOverview = '?view=table&sort=date'
      @r[:links][:up] = dirname + '/' + qs + '#r' + (path||'/').sha2 unless !path || path=='/'
      @r[:links][:down] = path + '/' if env['REQUEST_PATH'] && directory? && env['REQUEST_PATH'][-1] != '/'

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: ["\n\n",
                        {_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                             ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].justArray.map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             {_: :script, c: ["\n", SiteJS]}, "\n",
                             *@r[:links]&.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: ["\n", link[:up, '&#9650;'], {_: :a, id: :tabular, style: tabular ? 'color: #fff' : 'color: #555', href: tabular ? '?' : tabularOverview, c: '↨'},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             unless local?
                               {class: :toolbox,
                                c: {_: :a, id: :subscribe,
                                    href: '/' + (subbed ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + host + (@r['REQUEST_URI'] || path)}), class: subbed ? :on : :off, c: 'subscribe' + (subbed ? 'd' : '')}}
                             end,
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash @r), @r # 404
                             elsif q['group']
                               p = q['group']
                               case p
                               when 'to'
                                 p = To
                               when 'from'
                                 p = Creator
                               end
                               bins = {}
                               graph.map{|uri, resource|
                                 resource[p].justArray.map{|o|
                                   o = o.to_s
                                   bins[o] ||= []
                                   bins[o].push resource}}
                               bins.map{|bin, resources|
                                 {class: :group, style: HTML.colorize, c: [{_: :span, class: :label, c: CGI.escapeHTML(bin)}, HTML.tabular(resources, @r)]}}
                             elsif tabular
                               HTML.tabular graph, @r       # table layout
                             else
                               env[:graph] = graph
                               HTML.tree Treeize[graph], @r # tree layout
                             end,
                             link[:down,'&#9660;']]}]}]
    end

    def htmlGrep graph, q
      wordIndex = {}
      args = POSIX.splitArgs q
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      pattern = /(#{args.join '|'})/i

      # find matches
      graph.map{|k,v|
        graph.delete k unless (k.to_s.match pattern) || (v.to_s.match pattern)}

      # highlight matches in exerpt
      graph.values.map{|r|
        (r[Content]||r[Abstract]).justArray.map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).yield_self{|lines|
          r[Abstract] = lines[0..5].map{|l|
            l.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g}) # wrap in styled node
            }} if lines.size > 0 }}

      # CSS
      graph['#abstracts'] = {Abstract => HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})}
    end

    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || type.basename,
            c: [{_: :td, class: 'k', c: Markup[Type][type]},
                {_: :td, class: 'v', c: vs.justArray.map{|v|
                   [(value k, v, env), ' ']}}]}, "\n"] unless k=='uri' && vs.justArray[0].to_s.match?(/^_:/))}}
    end

    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      [{_: :a, class: :link, title: u, id: 'l'+rand.to_s.sha2,
        href: u, c: u.sub(/^https?.../,'')[0..127]}," \n"]}

    Markup[Type] = -> t, env=nil {
      if t.respond_to? :uri
        t = t.R
        {_: :a, href: t.uri,
         c: Icons[t.uri] || t.fragment || t.basename}
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Creator] = -> c, env, uris=nil {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R
        basename = u.basename
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        color = env[:colors][name] ||= HTML.colorize
        {_: :a, id: 'a'+rand.to_s.sha2, class: :creator, style: color, href: uris.justArray[0] || u.to_s, c: name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post , env {
      uri = post['uri'].justArray[0]
      post.delete 'uri'
      post.delete Type
      titles = post.delete(Title).justArray.map(&:to_s).map(&:strip).uniq
      date = post.delete(Date).justArray[0]
      from = post.delete(Creator).justArray
      to = post.delete(To).justArray
      images = post.delete(Image).justArray
      content = post.delete(Content).justArray
      uri_hash = 'r' + uri.sha2
      {class: :post, id: uri_hash,
       c: [{_: :a, id: 'pt' + uri_hash, class: :id, c: '☚', href: uri},
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               [{_: :a, id: 't'+rand.to_s.sha2, class: :title, href: uri, c: CGI.escapeHTML(title)}, ' ']
             end},
           ({_: :a, class: :date, id: 'date' + uri_hash, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date),
           images.map{|i| Markup[Image][i,env]},
           {_: :table, class: :fromTo,
            c: {_: :tr,
                c: [{_: :td, c: from.map{|f|Markup[Creator][f,env]}, class: :from},
                    {_: :td, c: '&rarr;'},
                    {_: :td, c: to.map{|f|Markup[Creator][f,env]}, class: :to}]}},
           content, ((HTML.keyval post, env) unless post.keys.size < 1)]}}

    Markup[Image] = -> image,env {
      img = image.R
      if env[:images] && env[:images][img.uri]
      # deduplicated
      else
        env[:images] ||= {}
        env[:images][img.uri] = true
        {class: :thumb, c: {_: :a, href: img.uri, c: {_: :img, src: img.uri}}}
      end}

    Markup[Video] = -> video,env {
      video = video.R
      if env[:images] && env[:images][video.uri]
      # deduplicated
      else
        env[:images] ||= {}
        env[:images][video.uri] = true
        if video.uri.match /youtu/
          id = (HTTP.parseQs video.query)['v'] || video.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, gesture: "media", allow: "encrypted-media", allowfullscreen: :true}
        else
          {class: :video,
           c: [{_: :video, src: video.uri, controls: :true}, '<br>',
               {_: :span, class: :notes, c: video.basename}]}
        end
      end}

    # Markup -> HTML
    def self.render x
      case x
      when String
        x
      when Hash # element
        void = [:img, :input, :link, :meta].member? x[:_]
        '<' + (x[:_] || 'div').to_s +                        # open
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # children
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close
      when Array
        x.map{|n|render n}.join
      when WebResource
        render({_: :a, href: x.uri, id: x[:id][0] || ('link'+rand.to_s.sha2), class: x[:class][0],
                c: x[:label][0] || (%w{gif ico jpeg jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML(x.uri[0..64]))})
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end

    def renderFeed graph
      HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                   {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                    c: [{_: :id, c: uri},
                        {_: :title, c: uri},
                        {_: :link, rel: :self, href: uri},
                        {_: :updated, c: Time.now.iso8601},
                        graph.map{|u,d|
                          {_: :entry,
                           c: [{_: :id, c: u}, {_: :link, href: u},
                               d[Date] ? {_: :updated, c: d[Date][0]} : nil,
                               d[Title] ? {_: :title, c: d[Title]} : nil,
                               d[Creator] ? {_: :author, c: d[Creator][0]} : nil,
                               {_: :content, type: :xhtml,
                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                    c: d[Content]}}]}}]}]
    end

    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Content, DC+'hasFormat', DC+'identifier', Image, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if attr == 'date'
        graph = graph.sort_by{|r| r[attr].justArray[0].to_s}.reverse
      end
      titles = {}
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p|
              p = p.R
              slug = p.fragment || p.basename
              icon = Icons[p.uri] || slug
              {_: :td, class: 'k', c: env[:query]['sort'] == p.uri ? icon : {_: :a, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
           graph.map{|resource|
             [{_: :tr, c: keys.map{|k|
                 {_: :td, class: 'v',
                  c: if k=='uri' # title with URI subscript
                   ts = resource[Title].justArray
                   if ts.size > 0
                     ts.map{|t|
                       title = t.to_s.sub(/\/u\/\S+ on /,'')
                       if titles[title]
                         {_: :a, href: resource['uri'], id: 'r' + rand.to_s.sha2, class: :id, c: '☚'}
                       else
                         titles[title] = true
                         {_: :a, href: resource['uri'], id: 'r' + rand.to_s.sha2, class: :title,
                          c: [(CGI.escapeHTML title), ' ',
                              {_: :span, class: :uri, c: CGI.escapeHTML(resource['uri'])}, ' ']}
                       end}
                   else
                     {_: :a, href: resource['uri'], id: 'r' + rand.to_s.sha2, class: :id, c: '&#x1f517;'}
                   end
                 else
                   resource[k].justArray.map{|v|value k, v, env }
                  end}}},
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Image].justArray.map{|i|{style: 'max-width: 20em', c: Markup[Image][i,env]}},
                                resource[Content]]}} if (resource[Content] || resource[Image]) && !env[:query]&.has_key?('head'))]}]}
    end

    def self.tree t, env, name=nil
      url = t[:RDF]['uri'] if t[:RDF]
      if name && t.keys.size > 1
        color = '#%06x' % rand(16777216)
        scale = rand(7) + 1
        position = scale * rand(960) / 960.0
        css = {style: "border: .08em solid #{color}; background: repeating-linear-gradient(#{rand 360}deg, #000, #000 #{position}em, #{color} #{position}em, #{color} #{scale}em)"}
      end

      {class: :tree,
       c: [({_: (url ? :a : :span), class: :label, c: (CGI.escapeHTML name.to_s)}.update(url ? {href: url} : {}) if name),
           t.map{|_name, _t|
             if :RDF == _name
               value nil, _t, env
             else
               tree _t, env, _name
             end
           }]}.update(css ? css : {})
    end

    # tree with nested S -> P -> O indexing (renderer input)
    def treeFromGraph graph
      g = {}                    # empty tree

      # traverse
      graph.each_triple{|s,p,o| # (subject,predicate,object) triple
        s = s.to_s; p = p.to_s  # subject, predicate
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
        g[s] ||= {'uri'=>s}                      # insert subject
        g[s][p] ||= []                           # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object

      g # tree
    end

    # Markup dispatcher
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # supplied type argument
        Markup[type][v,env]
      elsif v.class == Hash # RDF type
        resource = v.R
        types = resource.types
        if (types.member? Post) || (types.member? SIOC+'BlogPost') || (types.member? SIOC+'MailMessage')
          Markup[Post][v,env]
        elsif types.member? Image
          Markup[Image][v,env]
        else
          keyval v, env
        end
      elsif v.class == WebResource
        if v.uri.match?(/^_:/) && env[:graph] && env[:graph][v.uri] # blank-node
          value nil, env[:graph][v.uri], env
        elsif %w{jpeg jpg JPG png PNG webp}.member? v.ext           # image
          Markup[Image][v, env]
        else
          [v.data({label: CGI.escapeHTML((v.query || (v.basename && v.basename != '/' && v.basename) || (v.path && v.path != '/' && v.path) || v.host || v.to_s)[0..48])}), ' ']
        end
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end
  end
  include HTML
end

module Redcarpet
  module Render
    class Pygment < HTML
      def block_code(code, lang)
        if lang
          IO.popen("pygmentize -l #{lang.downcase.sh} -f html",'r+'){|p|
            p.puts code
            p.close_write
            p.read
          }
        else
          code
        end
      end
    end
  end
end

class String
  # text -> HTML, also yielding found (rel,href) tuples to block
  def hrefs &blk               # leading/trailing <>()[] and trailing ,. not captured in URL
    pre, link, post = self.partition(/(https?:\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub("\n",'<br>') + # pre-match
      (link.empty? && '' ||
       '<a class="link" href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = link.R
        if blk
          type = case link
                 when /(gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)$/i
                   WebResource::Image
                 when /(youtube.com|(mkv|mp4|webm)$)/i
                   WebResource::Video
                 else
                   WebResource::Link
                 end
          yield type, resource
        end
        CGI.escapeHTML(resource.uri.sub /^http:../,'')) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # prob not properly tail-recursive, getting overflow on logfiles, may need to rework
  rescue
    puts "failed to scan #{self}"
    ''
  end
  def sha2; Digest::SHA2.hexdigest self end
  def to_utf8; encode('UTF-8', undef: :replace, invalid: :replace, replace: '?') end
end
