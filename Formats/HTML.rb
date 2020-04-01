# coding: utf-8
module Webize
  module HTML
    include WebResource::URIs

    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script" # CSS selector for script elements

    # clean HTML (string)
    def self.clean body
      doc = Nokogiri::HTML.parse body.encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ') # parse to Nokogiri doc
      if content_type = doc.css('meta[http-equiv="Content-Type"]')[0] # in-band content-type tag found
        if content = content_type['content']
          if charset_tag = content.split(';')[1]
            if charset = charset_tag.split('=')[1]
              unless charset.match? /utf.?8/i
                doc = Nokogiri::HTML.parse body.force_encoding(charset).encode('UTF-8') # re-read with specified charset
              end
            end
          end
        end
      end
      clean_doc doc # clean nokogiri
      doc.to_html
    end

    # clean HTML (nokogiri instance)
    def self.clean_doc doc
      return if ENV.has_key? 'DIRTY'
      # strip fonts and preload-directives
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove

      # inspect resources
      log = []
      doc.css("iframe, img, [type='image'], link, script").map{|s|
        text = s.inner_text     # inline
        if s['type'] != 'application/json' && s['type'] != 'application/ld+json' && !text.match?(InitialState) && text.match?(GunkExec)
          log << "🚩 " + s.to_s.size.to_s + ' ' + text.match(GunkExec)[2][0..42]
          s.remove
        end
        %w(href src).map{|attr| # reference
          if s[attr]
            src = s[attr].R
            if src.gunkDomain? && !src.allowCDN?
              log << "🚫 \e[31;1;7m" + src.host + "\e[0m"
              s.remove
            elsif src.uri.match? Gunk
              log << "🚫 \e[31;1m" + src.uri + "\e[0m"
              s.remove
            end
          end}}
      puts log.join ' ' unless log.empty?
    end

    # format to local conventions
    def self.format body, base
      html = Nokogiri::HTML.fragment body
      html.css('iframe, style, link[rel="stylesheet"], ' + Scripts).remove
      clean_doc html                                                   # remove misc gunk

      # <img>
      html.css('[style*="background-image"]').map{|node|               # map references to classic image tag
        node['style'].match(/url\(['"]*([^\)'"]+)['"]*\)/).yield_self{|url|                                # CSS background-image
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}                            # amp image
      html.css("div[class*='image'][data-src]").map{|div|div.add_child "<img src=\"#{div['data-src']}\">"} # div image

      # identify <p> <pre> <ul> <ol>
      html.css('p').map{|e|   e.set_attribute 'id', 'p'   + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('pre').map{|e| e.set_attribute 'id', 'pre' + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('ul').map{|e|  e.set_attribute 'id', 'ul'  + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('ol').map{|e|  e.set_attribute 'id', 'ol'  + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}

      # <*>
      html.traverse{|e|
        e.attribute_nodes.map{|a| # inspect attrs
          e.set_attribute 'src', a.value if SRCnotSRC.member? a.name   # map @src-like attributes to @src
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/)||# strip attributes
                      %w(bgcolor class height http-equiv layout ping role style tabindex target theme width).member?(a.name)}
        if e['href']                                                   # resolve and annotate links
          ref = e['href'].R                                            # show full(er) URL in text
          e.add_child " <span class='uri'>#{CGI.escapeHTML e['href'].sub(/^https?:..(www.)?/,'')[0..127]}</span> "
          e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) unless e['id'] # identify node
          css = [:uri]; css.push :path if !ref.host || (ref.host == base.host) # local site or global link
          e['href'] = base.join e['href'] unless ref.host              # resolve relative references
          e['class'] = css.join ' '                                    # node CSS-class
        elsif e['id']                                                  # identified node without a link
          e.set_attribute 'class', 'identified'
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id']}</span> " unless e.name == 'p'
        end
        e['src'] = base.join e['src'] if e['src'] && !e['src'].R.host} # resolve media location

      html.to_xhtml indent: 0
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
      content_type 'text/html', extensions: [:htm, :html], aliases: %w(text/fragment+html;q=0.8)
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @opts = options
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
        @base = options[:base_uri]
        @base = @base.to_s[0..-6].R @base.env if @base.to_s.match? /\.html$/ # strip filename for generic Base-URI
        @opts[:noRDFa] = true if @base.to_s.match? /\/feed|polymer.*html/ # don't extract RDF from unpopulated templates
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
        scanContent{|s,p,o,g=nil|
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => g ? g.R : @base)}
      end

      # HTML -> RDF
      def scanContent &f
        subject = @base         # subject URI
        n = Nokogiri::HTML.parse @doc # parse

        # base URI
        if base = n.css('head base')[0]
          if baseHref = base['href']
            @base = @base.join(baseHref).R @base.env
          end
        end

        # bespoke triplr
        @base.send Triplr[@base.host], n, &f if Triplr[@base.host]

        # RDFa + JSON-LD
        unless @opts[:noRDFa]
          embeds = RDF::Graph.new
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}" # find JSON-LD triples
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"         # find RDFa triples
          embeds.each_triple{|s,p,o|
            p = MetaMap[p.to_s] || p # map predicates
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # show unresolved property-names
            yield s, p, o unless p == :drop} # emit triple
        end

        # embeds and links
        n.css('frame, iframe').map{|frame|
          if src = frame.attr('src')
            yield subject, Link, src.R
          end}

        n.css('[rel][href]').map{|m|
          if rel = m.attr("rel") # predicate
            if v = m.attr("href") # object
              rel.split(' ').map{|k|
                @base.env[:links][:prev] ||= v if k == 'prev'
                @base.env[:links][:next] ||= v if k == 'next'
                @base.env[:links][:feed] ||= v if k == 'alternate' && v.R.path&.match?(/^\/feed\/?$/)
                k = MetaMap[k] || k
                puts [k, v].join "\t" unless k.to_s.match? /^(drop|http)/
                yield subject, k, v.R unless k == :drop}
            end
          end}

        n.css('#next, #nextPage, a.next').map{|nextPage|
          if ref = nextPage.attr("href")
            @base.env[:links][:next] ||= ref
          end}

        n.css('#prev, #prevPage, a.prev').map{|prevPage|
          if ref = prevPage.attr("href")
            @base.env[:links][:prev] ||= ref
          end}

        # meta tags
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
          yield subject, Content, HTML.format(body.inner_html, @base).gsub(/<\/?noscript[^>]*>/i, '')
        else # no <body> element
          yield subject, Content, HTML.format(n.inner_html, @base).gsub(/<\/?noscript[^>]*>/i, '')
        end
      end
    end
  end
end

class WebResource

  # RDF data -> Hash tree indexed on s -> p -> o
  def treeFromGraph graph = nil
    graph ||= env[:repository]
    return {} unless graph

    tree = {}

    graph.each_triple{|s,p,o|
      s = s.to_s               # subject URI
      p = p.to_s               # predicate URI
      o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
      tree[s] ||= {'uri' => s} # insert subject
      tree[s][p] ||= []        # insert predicate
      if tree[s][p].class == Array
        tree[s][p].push o unless tree[s][p].member? o # insert in object array
          else
            tree[s][p] = [tree[s][p],o] unless tree[s][p] == o # new object array
      end}

    tree
  end

  module HTML
    include URIs

    # single-character representation of URI
    Icons = {
      Abstract => '✍',
      Audio => '🔊',
      Container => '📁',
      Content => '',
      Creator => '👤',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      DC + 'rights' => '⚖️',
      Date => '⌚', 'http://purl.org/dc/terms/created' => '⌚', 'http://purl.org/dc/terms/modified' => '⌚',
      Image => '🖼️',
      LDP + 'contains' => '📁',
      Link => '☛',
      Post => '📝',
      SIOC + 'BlogPost' => '📝',
      SIOC + 'MailMessage' => '✉️',
      SIOC + 'MicroblogPost' => '🐦',
      SIOC + 'attachment' => '✉',
      SIOC + 'generator' => '⚙',
      SIOC + 'reply_of' => '↩',
      SIOC + 'richContent' => '',
      Schema + 'height' => '↕',
      Schema + 'width' => '↔',
      Schema + 'DiscussionForumPosting' => '📝',
      Stat + 'File' => '📄',
      To => '☇',
      Type => '📕',
      Video => '🎞',
      W3 + '2000/01/rdf-schema#Resource' => '🌐',
    }

    Markup = {} # markup-generator lambdas

    MarkupMap = {
      'article' => Post,
      'http://schema.org/Comment' => Post,
      'http://schema.org/ProfilePage' => Person,
      'https://schema.org/BreadcrumbList' => List,
      'https://schema.org/Comment' => Post,
      'https://schema.org/ImageObject' => Image,
      'https://schema.org/NewsArticle' => Post,
      'https://schema.org/Person' => Person,
      FOAF + 'Image' => Image,
      SIOC + 'MicroblogPost' => Post,
      SIOC + 'BlogPost' => Post,
      SIOC + 'MailMessage' => Post,
      SIOC + 'UserAccount' => Person,
      Schema + 'Answer' => Post,
      Schema + 'Article' => Post,
      Schema + 'BlogPosting' => Post,
      Schema + 'BreadcrumbList' => List,
      Schema + 'Code' => Post,
      Schema + 'DiscussionForumPosting' => Post,
      Schema + 'ImageObject' => Image,
      Schema + 'ItemList' => List,
      Schema + 'NewsArticle' => Post,
      Schema + 'Person' => Person,
      Schema + 'Review' => Post,
      Schema + 'UserComments' => Post,
      Schema + 'VideoObject' => Video,
      Schema + 'WebPage' => Post,
    }

    def chrono_sort
      env[:sort] = 'date'
      env[:view] = 'table'
      self
    end

    def self.colorize color = '#%06x' % (rand 16777216)
      "color: black; background-color: #{color}; border-color: #{color}"
    end

    # Graph -> HTML
    def htmlDocument graph=nil
      graph ||= env[:graph] = treeFromGraph
      qs = query_values || {}
      env[:images] ||= {}
      env[:colors] ||= {}
      env[:links] ||= {}
      if env[:summary] || ((qs.has_key?('Q')||qs.has_key?('q')) && !qs.has_key?('fullContent'))
        expanded = HTTP.qs qs.merge({'fullContent' => nil})
        env[:links][:full] = expanded
        expander = {_: :a, id: :expand, c: '&#11206;', href: expanded}
      end
      chrono_sort if path.match? HourDir
      titleRes = ['', path, host && path && ('https://' + host + path)].compact.find{|u| graph[u] && graph[u][Title]}
      bc = '/' # breadcrumb path
      icon = ('//' + (host || 'localhost') + '/favicon.ico').R # site icon
      link = -> key, content { # render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url, id: key, class: :icon, c: content},
           "\n"]
        end}
      htmlGrep if localNode?

      # Markup -> HTML string
      HTML.render ["<!DOCTYPE html>\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             env[:links].map{|type,uri|
                               {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ]}, "\n",
                        {_: :body,
                         c: [{class: :toolbox,
                              c: [(icon.node.exist? && icon.node.size != 0) ? {_: :a, href: '/', id: :host, c: {_: :img, src: icon.uri}} : (host || 'localhost').split('.').-(%w(com net org www)).reverse.map{|h| {_: :a, class: :breadcrumb, href: '/', c: h}},
                                 ({_: :a, id: :tabular, class: :icon, style: 'color: #555', c: '↨',
                                    href: HTTP.qs(qs.merge({'view' => 'table', 'sort' => 'date'}))} unless qs['view'] == 'table'),
                                 parts.map{|p|
                                    [{_: :a, class: :breadcrumb, href: bc += p + '/', c: (CGI.escapeHTML Rack::Utils.unescape p), id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}, ' ']},
                                 link[:feed, FeedIcon], {_: :a, href: '?UI', c: '⚗️', id: :UI}]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash env), env
                             elsif (env[:view] || qs['view']) == 'table'
                               env[:sort] ||= qs['sort']
                               HTML.tabular graph, env
                             else
                               graph.values.map{|resource|
                                 HTML.value nil, resource, env}
                             end, expander,
                             {_: :script, c: SiteJS}]}]}]
    end

    def htmlGrep
      graph = env[:graph]
      qs = query_values || {}
      q = qs['Q'] || qs['q']
      return unless graph && q
      abbreviated = !qs.has_key?('fullContent')

      # query
      wordIndex = {}
      args = q.shellsplit rescue q.split(/\W/)
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      pattern = /(#{args.join '|'})/i

      # trim graph to matching resources
      graph.map{|k,v|
        graph.delete k unless (k.to_s.match pattern) || (v.to_s.match pattern)}

      # trim content to matching lines
      graph.values.map{|r|
        (r[Content]||r[Abstract]||[]).map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).yield_self{|lines|
          r[Abstract] = lines[0..7].map{|line|
            line.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # mark up matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g})
            }
          } if lines.size > 0
        }
        r.delete Content if abbreviated
      }

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
         ([{_: :tr, name: type.fragment || (type.path && type.basename),
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
        render [{_: :a, href: x.uri, c: (%w{gif ico jpeg jpg png webp}.member?(x.path && x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML((x.query || (x.path && x.basename != '/' && x.basename) || (x.path && x.path != '/' && x.path) || x.host || x.to_s)[0..48]))}, ' ']
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
            c: {_: :tr, c: keys.map{|p|
                  p = p.R
                  slug = p.fragment || (p.path && p.basename) || ' '
                  icon = Icons[p.uri] || slug
                  {_: :th, c: {_: :a, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}}},
           {_: :tbody,
            c: graph.map{|resource|

              re = (resource['uri'] || ('#' + Digest::SHA2.hexdigest(rand.to_s))).R
              local_id = re.path == env['REQUEST_PATH'] && re.fragment || ('r' + Digest::SHA2.hexdigest(re.uri))

              [{_: :tr, id: local_id, c: keys.map{|k|
                 [{_: :td, property: k,
                  c: if k == 'uri'
                   tCount = 0
                   [(resource[Title]||[]).map{|title|
                      title = title.to_s.sub(/\/u\/\S+ on /, '').sub /^Re: /, ''
                      unless env[:title] == title # show topic if changed from previous post
                        env[:title] = title; tCount += 1
                        {_: :a, href: re.uri, class: :title, type: :node, c: CGI.escapeHTML(title), id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}
                      end},
                    ({_: :a, href: re.uri, class: :id, type: :node, c: '🔗', id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} if tCount == 0),
                    (resource[SIOC+'reply_of']||[]).map{|r|
                      {_: :a, href: r.to_s, c: Icons[SIOC+'reply_of']} if r.class == RDF::URI || r.class == WebResource},
                    resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                    [Image,
                     Video].map{|t|(resource[t]||[]).map{|i|
                                         Markup[t][i,env]}},
                    [resource[Content], resource[SIOC+'richContent']].compact.join('<hr>'),
                    MarkupLinks[(resource[Link]||[]),env]]
                 else
                   (resource[k]||[]).map{|v|value k, v, env }
                   end}, "\n"
                 ]}}, "\n"
              ]}}]}
    end


    # Value -> Markup
    def self.value type, v, env
      if [Abstract, Content, 'http://rdfs.org/sioc/ns#richContent'].member? type
        v                # prepared HTML content
      elsif Markup[type] # markup lambda defined for explicit type argument
        Markup[type][v,env]
      elsif v.class == Hash # data
        types = (v[Type] || []).map{|t|
          MarkupMap[t.to_s] || t.to_s } # normalize typetags for unified renderer selection
        seen = false
        [types.map{|type|
          if markup = Markup[type] # markup lambda defined for RDF type
            seen = true
            markup[v,env]
          end},
         (keyval v, env unless seen)] # default key-value renderer
      elsif v.class == WebResource # resource-reference arguments
        if v.path && %w{jpeg jpg JPG png PNG webp}.member?(v.ext)
          Markup[Image][v, env]    # image reference
        else
          v                        # generic reference
        end
      else # undefined renderer
        CGI.escapeHTML v.to_s
      end
    end

    # markup lambdas

    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Audio] = -> audio, env {
      src = (if audio.class == WebResource
             audio
            elsif audio.class == String && audio.match?(/^http/)
              audio
            else
              audio['https://schema.org/url'] || audio[Schema+'contentURL'] || audio[Schema+'url'] || audio[Link] || audio['uri']
             end).to_s
       {class: :audio,
           c: [{_: :audio, src: src, controls: :true}, '<br>',
               {_: :a, href: src, c: src.R.basename}]}
    }

    Markup[Container] = -> dir , env { uri = (dir.delete('uri') || '').R
      [Type, Title,
       W3 + 'ns/posix/stat#mtime',
       W3 + 'ns/posix/stat#size'].map{|p|dir.delete p}
      {class: :container,
       c: [{_: :a, id: 'container' + Digest::SHA2.hexdigest(rand.to_s), class: :title, href: uri.path, type: :node, c: uri.basename},
           {class: :body, c: HTML.keyval(dir, env)}]}}

    Markup[Creator] = Markup[To] = Markup['http://xmlns.com/foaf/0.1/maker'] = -> c, env {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R
        basename = u.basename if u.path
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        avatar = nil
        {_: :a, href: u.to_s,
         id: 'a' + Digest::SHA2.hexdigest(rand.to_s),
         class: avatar ? :avatar : :fromto,
         style: avatar ? '' : (env[:colors][name] ||= HTML.colorize),
         c: avatar ? {_: :img, class: :avatar, src: avatar} : name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, c: date, href: 'http://' + (ENV['HOSTNAME'] || 'localhost') + ':8000/' + date[0..13].gsub(/[-T:]/,'/')}}

    Markup['http://purl.org/dc/terms/created'] = Markup['http://purl.org/dc/terms/modified'] = Markup[Date]

    Markup[DC+'language'] = -> lang, env=nil {
      {'de' => '🇩🇪',
       'en' => '🇬🇧',
       'fr' => '🇫🇷',
       'ja' => '🇯🇵',
      }[lang] || lang
    }

    MarkupLinks = -> links, env=nil{
      {_: :table, class: :links,
       c: links.group_by{|l|l.R.host}.map{|host, paths|
         {_: :tr,
          c: [{_: :td, class: :host, c: host ? {_: :a, href: '//' + host, c: host, style: (env[:colors][host] ||= HTML.colorize)[14..-1].sub('background-','')} : []},
              {_: :td, c: paths.map{|path| Markup[Link][path,env]}}]}}}}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      re = u.R
      [{_: :a, href: u, c: (re.path||'/')[0..79], title: u,
        id: 'l' + Digest::SHA2.hexdigest(rand.to_s),
        style: env[:colors][re.host] ||= HTML.colorize},
       " \n"]}

    Markup[List] = -> list, env {
      tabular((list[Schema+'itemListElement']||list[Schema+'ListItem']||
               list['https://schema.org/itemListElement']||[]).map{|l|
                l.respond_to?(:uri) && env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri, Title => [l.uri]} : l)}, env)}

    Markup[Post] = -> post, env {
      post.delete Type
      uri = post.delete('uri') || ('#' + Digest::SHA2.hexdigest(rand.to_s))
      resource = uri.R
      titles = (post.delete(Title)||[]).map(&:to_s).map(&:strip).compact.-([""]).uniq
      abstracts = post.delete(Abstract) || []
      date = (post.delete(Date) || [])[0]
      from = post.delete(Creator) || []
      to = post.delete(To) || []
      images = post.delete(Image) || []
      links = post.delete(Link) || []
      content = post.delete(Content) || []
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
      hasPointer = false
      local_id = resource.path == env['REQUEST_PATH'] && resource.fragment || uri_hash
      {class: :post, id: local_id,
       c: ["\n",
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               hasPointer = true
               [{_: :a, class: :title, type: :node, href: uri, c: CGI.escapeHTML(title), id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}, " \n"]
             end},
           ({_: :a, class: :id, type: :node, c: '🔗', href: uri, id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} unless hasPointer), "\n", # pointer
           abstracts,
           ([{_: :a, class: :date, href: '/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date}, "\n"] if date),
           images.map{|i| Markup[Image][i,env]},
           {_: :table,
            c: {_: :tr,
                c: [{_: :td,
                     c: from.map{|f|Markup[Creator][f,env]},
                     class: :from}, "\n",
                    {_: :td, c: '&rarr;'},
                    {_: :td,
                     c: [to.map{|f|Markup[To][f,env]},
                         post.delete(SIOC+'reply_of')],
                     class: :to}, "\n"]}}, "\n",
           content,
           MarkupLinks[links, env],
           (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}}

    Markup[Stat+'File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons[Stat+'File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

    Markup[Title] = -> title, env {
      if title.class == String
        {_: :h3, class: :title, c: CGI.escapeHTML(title)}
      end}

    Markup[Type] = -> t, env=nil {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || (t.path && t.basename)}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Image] = -> image,env {
      src = if image.class == WebResource
              image.to_s
            elsif image.class == String && image.match?(/^([\/]|http)/)
              image
            else
              image['https://schema.org/url'] || image[Schema+'url'] || image[Link] || image['uri']
            end
      if src.class == Array
        puts "multiple img-src found:", src if src.size > 1
        src = src[0]
      end
      [{class: :thumb, c: {_: :a, href: src, c: {_: :img, src: src}}}, " \n"]}

    Markup[Video] = -> video, env {
      src = if video.class == WebResource || (video.class == String && video.match?(/^http/))
              video
            else
              video['https://schema.org/url'] || video[Schema+'contentURL'] || video[Schema+'url'] || video[Link] || video['uri']
            end
      if src.class == Array
        puts "multiple video-src found:", src if src.size > 1
        src = src[0]
      end
      src = src.to_s
      if src.match /v.redd.it/
        src += '/DASHPlaylist.mpd'
        dash = true
      end
      v = src.R
      unless env[:images][src]
        env[:images][src] = true
        if src.match /youtu/
          id = (v.query_values||{})['v'] || v.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, allowfullscreen: :true}
        else
          [dash ? '<script src="https://cdn.dashjs.org/latest/dash.all.min.js"></script>' : nil,
           {class: :video,
           c: [{_: :video, src: src, controls: :true}.update(dash ? {'data-dashjs-player' => 1} : {}), '<br>',
               ({_: :a, href: src, c: v.basename} if v.path)]}]
        end
      end}
  end

  include HTML
end
