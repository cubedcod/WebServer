# coding: utf-8
require 'nokogiri'
module Webize
  module HTML
    def self.clean body
      # parse input
      html = Nokogiri::HTML.fragment body

      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}

      # strip Javascript and tracker-images
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{quantserve scorecardresearch}.map{|co| # TODO apply nofetch rules
        html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # map CSS:background-image → <img>
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}

      # map <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}

      html.traverse{|e|
        e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) if e['href'] && !e['id'] # link identifier
        e.attribute_nodes.map{|a|
          # normalize @src
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name

          # strip attributes
          dropa = a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || # script gunk
                  %w{bgcolor class height http-equiv layout ping role style tabindex target width}.member?(a.name) || # misc attrs
                  a.name == 'id' && e.name != 'a' # non-anchor elements with id
          a.unlink if dropa}}

      # output
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
header  [class*='header']  [id*='header'] [class*='Header'] [id*='Header']
nav     [class^='nav']     [id^='nav']
sidebar [class^='side']    [id^='side']
}

      def initialize(input = $stdin, options = {}, &block)
        @opts = options
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
        @base = options[:base_uri].R

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
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, n, &f
        end

        # embedded graph-data in RDFa, JSON-LD
        unless @opts[:no_embeds]
          embeds = RDF::Graph.new
          # JSON-LD
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"
          # RDFa
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"
          # emit normalized triples
          embeds.each_triple{|s,p,o|
            p = MetaMap[p.to_s] || p # predicate map
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # notify on unmapped predicate
            yield s, p, o unless p == :drop}
        end

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
              k = MetaMap[k] || k                  # normalize predicates
              case k                           # per-predicate custom processing
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
                                # notify on predicates lacking HTTP mapping
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield subject, k, v unless k == :drop # meta-tag RDF
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
              #puts "X"*80,"stripping #{selector}:", sel
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

    Avatars = {}
    'avatars/*png'.R.glob.map{|a|
      Avatars[Base64.decode64(a.basename.split('.')[0]).downcase] = ServerAddr + a.path}

    def avatar link = nil
      location = ('avatars/' + Base64.encode64(uri).gsub("\n",'') + '.png').R
      location.write open(link).read if link
      location
    end

    def self.colorize color = '#%06x' % (rand 16777216)
      "color: black; background-color: #{color}; border-color: #{color}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph = {}

      # HEAD links
      @r ||= {query: {}}
      @r[:links] ||= {}
      @r[:images] ||= {}
      @r[:colors] ||= {}

      # title  TODO Canonicalize URIs in graphToTree? lookup all potential combinations here
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
          [{_: :a, href: url, id: key, class: :icon, c: displayname},
           "\n"]
          end}

      htmlGrep graph, env[:query]['q'] if env[:GrepRequest]
      subbed = subscribed?
      tabular = env[:query]['view'] == 'table' || uri == '//www.w3.org/1999/02/22-rdf-syntax-ns'
      shrunken = env[:query].has_key? 'head'
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
                                  {_: :a, id: :tabular, class: :icon, style: tabular  ? 'color: #fff' : 'color: #555', href: HTTP.qs(tabular  ? env[:query].reject{|k,v|k=='view'} : env[:query].merge({'view' => 'table', 'sort' => 'date'})), c: '↨'},
                                  {_: :a, id: :shrink,  class: :icon, style: shrunken ? 'color: #fff' : 'color: #555', href: HTTP.qs(shrunken ? env[:query].reject{|k,v|k=='head'} : env[:query].merge({'head' => ''})), c: shrunken ? '&#9661;' : '&#9651;'},
                                  unless local?
                                    [{_: :a, id: :ui, class: :icon, style: 'color: #555', href: HTTP.qs(env[:query].merge({'ui' => 'upstream'})), c: '⚗'},
                                     {_: :a, id: :subscribe, href: '/' + (subbed ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + (host||env['SERVER_NAME']) + (@r['REQUEST_URI'] || path)}), class: subbed ? :on : :off, c: 'subscribe' + (subbed ? 'd' : '')}]
                                  end]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash @r), @r # 404
                             elsif tabular
                               HTML.tabular graph, @r       # table
                             else
                               HTML.tree Treeize[graph], @r # tree
                             end,
                             link[:down,'&#9660;']]}]}]
    end

    # Hash -> Markup
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
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Video, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if attr == 'date'
        attr = Content if attr == 'content'
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
              {_: :td, c: (env[:query]||{})['sort'] == p.uri ? icon : {_: :a, class: :head, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
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
                  end}}}.update(resource['uri'] && resource['uri'].R.path == env['REQUEST_PATH'] && {id: resource['uri'].R.fragment} || {}),
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                                (resource[Image]||[]).map{|i| {style: 'max-width: 28em', c: Markup[Image][i,env]}},
                                (resource[Video]||[]).map{|i| {style: 'max-width: 32em', c: Markup[Video][i,env]}},
                                resource[Content]]}} if contentRow)]}]}
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
      {class: :tree,
       c: [({_: :a, href: url, c: CGI.escapeHTML(name.to_s[0..85])} if name && url),
           t.map{|_name, _t|
             _name == :RDF ? (value nil, _t, env) : (tree _t, env, _name)}]}.update(css ? css : {})
    end

    # Value -> Markup
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # supplied type argument
        Markup[type][v,env]
      elsif v.class == Hash # RDF type
        # TODO just render (potentially N times) for each type with a defined renderer?
        # could simplify this but we'd need deduplication and type-merging that way also
        types = (v[Type]||[]).map &:R
        if (types.member? Post) || (types.member? SIOC+'BlogPost') || (types.member? SIOC+'MailMessage') || (types.member? Schema+'DiscussionForumPosting') || (types.member? Schema+'Answer') || (types.member? Schema+'Review') || (types.member? 'https://schema.org/Comment') || (types.member? Schema+'NewsArticle')
          Markup[SIOC+'MailMessage'][v,env]
        elsif (types.member? Image) || (types.member? Schema+'ImageObject') || (types.member? 'https://schema.org/ImageObject')
          Markup[Image][v,env]
        elsif types.member? LDP+'Container'
          Markup[LDP+'Container'][v,env]
        elsif types.member? Stat+'File'
          Markup[Stat+'File'][v,env]
        elsif (types.member? Schema+'BreadcrumbList') || (types.member? 'https://schema.org/BreadcrumbList')
          Markup[Schema+'BreadcrumbList'][v,env]
        elsif (types.member? SIOC+'UserAccount') || (types.member? Schema+'Person') || (types.member? 'https://schema.org/Person')
          Markup[SIOC+'UserAccount'][v,env]
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

    Markup[Type] = -> t, env=nil {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || t.basename}.update(Icons[t.uri] ? {} : {style: 'font-weight: bold'})
      else
        CGI.escapeHTML t.to_s
      end}

  end
end
