# coding: utf-8
require 'nokogiri'
module Webize
  module HTML
    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body

      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}

      # strip Javascript and tracker-images
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{quantserve scorecardresearch}.map{|co|
        html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # CSS:background-image → <img>
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      # <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}

      # traverse nodes
      html.traverse{|e|
        e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) if e['href'] && !e['id'] # link identifier
        e.attribute_nodes.map{|a|
          # move nonstandard src attrs
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height layout ping role style tabindex target width}.member?(a.name)}}

      # unparse
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
aside   [class*='aside']   [id*='aside']
footer  [class^='footer']  [id^='footer']
header  [class*='header']  [id*='header'] [class*='Header'] [id*='Header']
nav     [class^='nav']     [id^='nav']
sidebar [class^='side']    [id^='side']
}

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
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
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      # HTML -> RDF
      def scanContent &f
        embeds = RDF::Graph.new # embedded graph-data
        subject = @base         # subject URI
        n = Nokogiri::HTML.parse @doc # parse

        # host bindings
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, n, &f
        end

        # read JSON-LD
        n.css('script[type="application/ld+json"]').map{|dataElement|
          embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"

        # read RDFa
        RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"

        # normalized JSON-LD/RDFa
        embeds.each_triple{|s,p,o|
          p = MetaMap[p.to_s] || p
          puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/
          yield s, p, o unless p == :drop}

        # <link>
        n.css('head link[rel]').map{|m|
          if k = m.attr("rel") # predicate
            if v = m.attr("href") # object
              k = MetaMap[k] || ('#' + k.gsub(' ','_'))
              yield subject, k, v.R unless k == :drop
            end
          end}

        # <meta>
        n.css('head meta').map{|m|
          if k = (m.attr("name") || m.attr("property")) # predicate
            if v = m.attr("content")                    # object
              k = MetaMap[k] || k
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
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
        if body = n.css('body')[0]
          %w{content-body entry-content}.map{|bsel|
            if content = body.css('.' + bsel)[0]
              yield subject, Content, HTML.clean(content.inner_html)
            end}
          [*BasicGunk,*Gunk].map{|selector|
            body.css(selector).map{|sel|
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
    include URIs

    Avatars = {}
    'avatars/*png'.R.glob.map{|a|
      Avatars[Base64.decode64(a.basename.split('.')[0]).downcase] = 'http://localhost:8000' + a.path
    }

    def avatar link = nil
      location = ('avatars/' + Base64.encode64(uri).gsub("\n",'') + '.png').R
      location.writeFile open(link).read if link
      location
    end

    Markup = {}

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
      ].compact.find{|u|
        graph[u] && graph[u][Title]}

      # render HEAD link as HTML
      link = -> key, displayname {
        if url = @r[:links][key]
          [{_: :a, href: url, id: key, c: displayname},
           "\n"]
          end}


      htmlGrep graph, q['q'] if @r[:grep]
      subbed = subscribed?

      tabular = q['view'] == 'table'
      shrunken = q.has_key? 'head'
      @r[:links][:up] = dirname + (dirname[-1] == '/' ? '' : '/') + qs + '#r' + Digest::SHA2.hexdigest(path||'/') unless !path || path == '/'
      @r[:links][:down] = path + '/' if env['REQUEST_PATH'] && node.directory? && env['REQUEST_PATH'][-1] != '/'

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                             ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             {_: :script, c: ["\n", SiteJS]}, "\n",
                             *@r[:links]&.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: [{class: :toolbox,
                              c: [link[:up, '&#9650;'],
                                  {_: :a, id: :tabular, style: tabular ? 'color: #fff' : 'color: #555', href: HTTP.qs(tabular ? q.reject{|k,v|k=='view'} : q.merge({'view' => 'table', 'sort' => 'date'})), c: '↨'},
                                  {_: :a, id: :shrink, style: shrunken ? 'color: #fff' : 'color: #555', href: HTTP.qs(shrunken ? q.reject{|k,v|k=='head'} : q.merge({'head' => ''})), c: shrunken ? '&#9661;' : '&#9651;'},
                                  unless local?
                                    [{_: :a, id: :ui, style: 'color: #555', href: HTTP.qs(q.merge({'ui' => 'upstream'})), c: '⚗'},
                                     {_: :a, id: :subscribe, href: '/' + (subbed ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + host + (@r['REQUEST_URI'] || path)}), class: subbed ? :on : :off, c: 'subscribe' + (subbed ? 'd' : '')}]
                                  end]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
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
                                 resource[p].map{|o|
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
        (r[Content]||r[Abstract]||[]).map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).yield_self{|lines|
          r[Abstract] = lines[0..5].map{|l|
            l.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g}) # wrap in styled node
            }} if lines.size > 0 }}

      # CSS
      graph['#abstracts'] = {Abstract => [HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})]}
    end

    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || type.basename,
            c: [{_: :td, class: 'k', c: Markup[Type][type]},
                {_: :td, class: 'v', c: vs.map{|v|
                   [(value k, v, env), ' ']}}]}, "\n"] unless k=='uri' && vs[0] && vs[0].to_s.match?(/^_:/))}}
    end

    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      avatar = Avatars[u.gsub(/\/$/,'')]
      [{_: :a,
        c: avatar ? {_: :img, class: :avatar, src: avatar} : u.sub(/^https?.../,'')[0..79],
        href: u,
        id: 'l' + Digest::SHA2.hexdigest(rand.to_s),
        style: avatar ? 'background-color: #000' : (env[:colors][u.R.host] ||= HTML.colorize),
        title: u,
       },
       " \n"]}

    Markup[Type] = -> t, env=nil {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || t.basename}
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Creator] = Markup[To] = -> c, env {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R
        basename = u.basename
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        avatar = Avatars[u.to_s.downcase]
        [{_: :a, href: u.to_s, id: 'a' + Digest::SHA2.hexdigest(rand.to_s),
          class: :creator,
          style: avatar ? 'background-color: #000' : (env[:colors][name] ||= HTML.colorize),
          c: avatar ? {_: :img, class: :avatar, src: avatar} : name}, ' ']
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post , env {
      post.delete Type
      uri = post.delete 'uri'
      titles = (post.delete(Title)||[]).map(&:to_s).map(&:strip).uniq
      date = (post.delete(Date) || [])[0]
      from = post.delete(Creator) || []
      to = post.delete(To) || []
      images = post.delete(Image) || []
      content = post.delete(Content) || []
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
      {class: :post, id: uri_hash,
       c: [{_: :a, id: 'pt' + uri_hash, class: :id, c: '☚', href: uri},
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               [{_: :a, id: 't' + Digest::SHA2.hexdigest(rand.to_s), class: :title, href: uri, c: CGI.escapeHTML(title)}, ' ']
             end},
           ({_: :a, class: :date, id: 'date' + uri_hash, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date),
           images.map{|i| Markup[Image][i,env]},
           {_: :table, class: :fromTo,
            c: {_: :tr,
                c: [{_: :td,
                     c: from.map{|f|Markup[Creator][f,env]},
                     class: :from},
                    {_: :td, c: '&rarr;'},
                    {_: :td,
                     c: [to.map{|f|Markup[To][f,env]},
                         post.delete(SIOC+'reply_of')],
                     class: :to}]}},
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
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Video, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if attr == 'date'
        graph = graph.sort_by{|r|
          if values = r[attr]
            values[0].to_s
          else
            ''
          end
         }.reverse
      end
      titles = {}
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p|
              p = p.R
              slug = p.fragment || p.basename
              icon = Icons[p.uri] || slug
              {_: :td, c: env[:query]['sort'] == p.uri ? icon : {_: :a, class: :head, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
           graph.map{|resource|
             contentRow = resource[Abstract] || resource[Content] || resource[Image] || resource[Video]
             [{_: :tr, c: keys.map{|k|
                 {_: :td,
                  c: if k == 'uri'
                   ts = resource[Title] || []
                   if ts.size > 0
                     ts.map{|t|
                       title = t.to_s.sub(/\/u\/\S+ on /,'')
                       if titles[title]
                         {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :id, c: '☚'}
                       else
                         titles[title] = true
                         {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :title,
                          c: [(CGI.escapeHTML title), ' ',
                              #{_: :span, class: :uri, c: CGI.escapeHTML(resource['uri'][0..96])},
                              ' ']}
                       end}
                   else
                     {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :id, c: '&#x1f517;'}
                   end
                 else
                   (resource[k]||[]).map{|v|value k, v, env }
                  end}}},
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                                (resource[Image]||[]).map{|i| {style: 'max-width: 28em', c: Markup[Image][i,env]}},
                                (resource[Video]||[]).map{|i| {style: 'max-width: 32em', c: Markup[Video][i,env]}},
                                resource[Content]]}} if contentRow)]}]}
    end

    def self.tree t, env, name=nil
      url = t[:RDF]['uri'] if t[:RDF]
      css = {style: "background-color: #{'#%06x' % rand(16777216)}"} if name && t.keys.size > 1
      {class: :tree,
       c: [({_: (url ? :a : :span), c: (CGI.escapeHTML name.to_s[0..85])}.update(url ? {href: url} : {}) if name),
           t.map{|_name, _t|
             _name == :RDF ? (value nil, _t, env) : (tree _t, env, _name)}]}.update(css ? css : {})
    end

    # tree with S -> P -> O indexing
    def treeFromGraph graph ; tree = {}
      head = q.has_key? 'head'
      graph.each_triple{|s,p,o|
        s = s.to_s; p = p.to_s # subject URI, predicate URI
        unless head && p == Content
          o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
          tree[s] ||= {'uri' => s}                      # subject
          tree[s][p] ||= []                             # predicate
          tree[s][p].push o unless tree[s][p].member? o # object
        end}
      tree
    end

    # Markup dispatcher
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # supplied type argument
        Markup[type][v,env]
      elsif v.class == Hash # RDF type
        types = (v[Type]||[]).map &:R
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
          v
        end
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end
  end
  include HTML
end
