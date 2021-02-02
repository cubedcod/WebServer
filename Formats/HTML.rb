# coding: utf-8
module Webize
  module HTML
    include WebResource::URIs

    def self.clean doc, base
      doc = Nokogiri::HTML.parse doc.gsub /<\/?(form|noscript)[^>]*>/i, '' # strip <noscript>,<form> and parse

      doc.traverse{|e|

        if e['src']                                  # src attribute
          src = (base.join e['src']).R               # resolve src location
          if src.deny?
            puts "🚩 \e[31;1m#{src}\e[0m" if Verbose
            e.remove                                 # strip blocked src
          end
        end

        if e['href']                                 # href attribute
          ref = (base.join e['href']).R              # resolve href location
          if ref.deny?
            puts "🚩 \e[31;1m#{ref}\e[0m" if Verbose
            e.remove                                 # strip blocked href
          end
        end}

      doc.css('meta[content]').map{|meta|
        if meta['content'].match? /^https?:/
          meta.remove if meta['content'].R.deny?
        end}

      doc.css('script').map{|s|
        if gunk = (s.inner_text.match ScriptGunk)
          base.env[:log].push gunk.to_s[0..31] if Verbose
          puts s.inner_text, '-'*42 if Verbose
          s.remove
        end}

      doc.css('style').map{|s| Webize::CSS.cleanNode s if s.inner_text.match? /font-face|import/}

      doc.css("amp-ad, amp-consent, [class*='modal'], [class*='newsletter'], [class*='overlay'], .player-unavailable").remove

      doc.to_html
    end

    # format HTML to local preferences
    def self.format html, base
      html = Nokogiri::HTML.fragment html if html.class == String

      # drop nonlocal formatting, embeds, code and input controls
      html.css('iframe, input, script, style, a[href^="javascript"], link[rel="stylesheet"], link[type="text/javascript"], link[as="script"]').remove unless [nil,'localhost'].member? base.host

      # <img> mapping
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(/url\(['"]*([^\)'"]+)['"]*\)/).yield_self{|url|                                # CSS background-image -> img
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp| amp.add_child "<img src=\"#{amp['src']}\">"}                           # amp-img -> img
      html.css("div[class*='image'][data-src]").map{|div|div.add_child "<img src=\"#{div['data-src']}\">"} # div -> img
      html.css("figure[itemid]").map{|fig| fig.add_child "<img src=\"#{fig['itemid']}\">"}                 # figure -> img
      html.css("slide").map{|s| s.add_child "<img src=\"#{s['original']}\" alt=\"#{s['caption']}\">"}      # slide -> img

      html.traverse{|e|                                              # visit nodes
        e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # inspect attributes
          e.set_attribute 'src', a.value if SRCnotSRC.member? a.name # map src-like attributes to src
          e.set_attribute 'srcset', a.value if SRCSET.member? a.name # map srcset-like attributes to srcset
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w(bgcolor class color height http-equiv layout loading ping role style tabindex target theme width).member?(a.name)}
        e['src'] = (base.join e['src']) if e['src']                  # resolve @src
        srcset e, base if e['srcset']                                # resolve @srcset
        if e['href']                                                 # href attribute
          ref = (base.join e['href']).R                              # resolve href location
          ref.query = '' if ref.query&.match?(/utm[^a-z]/)           # de-urchinize query
          ref.fragment = '' if ref.fragment&.match?(/utm[^a-z]/)     # de-urchinize fragment
          offsite = ref.host != base.host
          e.add_child " <span class='uri'>#{CGI.escapeHTML (offsite ? ref.uri.sub(/^https?:..(www.)?/,'') : (ref.path || '/'))[0..127]}</span> " # show URI in HTML
          e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) unless e['id'] # mint identifier
          css = [:uri]; css.push :path unless offsite                # style as local or global reference
          e['href'] = ref.href                                       # update href to resolved location
          e['class'] = css.join ' '                                  # add CSS style
        elsif e['id']                                                # id attribute w/o href
          e.set_attribute 'class', 'identified'                      # style as identified node
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id'] unless e.name == 'p'}</span> " # add href to node
        end}

      html.to_xhtml indent: 0                                        # serialize
    end

    class Format < RDF::Format
      content_type 'text/html', extensions: [:htm, :html], aliases: %w(text/fragment+html;q=0.8)
      content_encoding 'utf-8'
      reader { Reader }
    end

    # HTML document -> RDF
    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @doc = Nokogiri::HTML.parse input.respond_to?(:read) ? input.read : input.to_s

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
          if p.to_s == Date # normalize date formats
            o = o.to_s
            o = if o.match?(/^\d+$/) # unixtime
                  Time.at o.to_i
                elsif o.empty?
                  nil
                else
                  Time.parse o rescue puts("failed to parse time: #{o}")
                end
            o = o.utc.iso8601 if o
          end
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     graph_name: g ? g.R : @base) if o
        }
      end

      def scanContent &f
        subject = @base         # subject URI
        n = @doc

        # base URI declaration
        if base = n.css('head base')[0]
          if baseHref = base['href']
            @base = @base.join(baseHref).R @base.env
          end
        end

        # site-specific reader
        @base.send Triplr[@base.host], n, &f if Triplr[@base.host]

        # embedded frames
        n.css('frame, iframe').map{|frame|
          if src = frame.attr('src')
            src = @base.join(src).R
            yield subject, Link, src unless src.deny?
          end}

        # typed references
        n.css('[rel][href]').map{|m|
          if rel = m.attr("rel") # predicate
            if v = m.attr("href") # object
              v = @base.join v
              rel.split(/[\s,]+/).map{|k|
                @base.env[:links][:prev] ||= v if k.match? /prev(ious)?/i
                @base.env[:links][:next] ||= v if k.downcase == 'next'
                @base.env[:links][:icon] ||= v if k.match? /^(fav)?icon?$/i
                @base.env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/))) && !@base.env[:feeds].member?(v)
                k = MetaMap[k] || k
                puts [k, v].join "\t" unless k.to_s.match? /^(drop|http)/
                yield subject, k, v unless k == :drop}
            end
          end}

        # page  pointers
        n.css('#next, #nextPage, a.next').map{|nextPage|
          if ref = nextPage.attr("href")
            @base.env[:links][:next] ||= ref
          end}

        n.css('#prev, #prevPage, a.prev').map{|prevPage|
          if ref = prevPage.attr("href")
            @base.env[:links][:prev] ||= ref
          end}

        # meta tags
        n.css('meta').map{|m|
          if k = (m.attr("name") || m.attr("property"))  # predicate
            if v = (m.attr("content") || m.attr("href")) # object
              k = MetaMap[k] || k                        # map property-names
              case k
              when Abstract
                v = v.hrefs
              when /lytics/
                k = :drop
              else
                v = @base.join v if v.match? /^(http|\/)\S+$/
              end
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield subject, k, v unless k == :drop
            end
          elsif m['http-equiv'] == 'refresh'
            yield subject, Link, m['content'].split('url=')[-1].R
          end}

        # <title>
        n.css('title').map{|title| yield subject, Title, title.inner_text }

        # <video>
        ['video[src]', 'video > source[src]'].map{|vsel|
          n.css(vsel).map{|v|
            yield subject, Video, @base.join(v.attr('src')) }}

        # HFeed
        @base.HFeed n, &f 

        # RDFa + JSON-LD + Microdata
        unless @base.to_s.match? /\/feed|polymer.*html/ # don't look for RDF in unpopulated templates
          embeds = RDF::Graph.new
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"   # JSON-LD triples
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"           # RDFa triples
          RDF::Reader.for(:microdata).new(@doc, base_uri: @base){|_| embeds << _ } rescue "Microdata read failure in #{@base}" # Microdata triples
          embeds.each_triple{|s,p,o| # inspect  raw triple
            p = MetaMap[p.to_s] || p # map predicates
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # show unresolved property-names
            yield s, p, o unless p == :drop} # emit triple
        end

        # JSON
        n.css('script[type="application/json"], script[type="text/json"]').map{|json|
          Webize::JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        # <body>
        if body = n.css('body')[0]
          unless @base.local_node? || (@base.query_values||{}).has_key?('fullContent') # summarize to new content
            @base.env[:summary] = true
            hashed_nodes = 'div, footer, h1, h2, h3, nav, p, section, span'
            hashs = {}
            links = {}
            hashfile = ('//' + @base.host + '/.hashes').R
            linkfile = ('//' + @base.host + '/.links.u').R
            if linkfile.node.exist?
              site_links = {}
              linkfile.node.each_line{|l| site_links[l.chomp] = true}
              body.css('a[href]').map{|a|
                links[a['href']] = true
                a.remove if site_links.has_key?(a['href'])}
            else
              body.css('a[href]').map{|a|
                links[a['href']] = true}
            end
            if hashfile.node.exist?
              site_hash = {}
              hashfile.node.each_line{|l| site_hash[l.chomp] = true}
              body.css(hashed_nodes).map{|n|
                hash = Digest::SHA2.hexdigest n.to_s
                hashs[hash] = true
                n.remove if site_hash.has_key?(hash)}
            else
              body.css(hashed_nodes).map{|n|
                hash = Digest::SHA2.hexdigest n.to_s
                hashs[hash] = true}
            end
            hashfile.writeFile hashs.keys.join "\n" # update hashfile
            linkfile.writeFile links.keys.join "\n" # update linkfile
          end

          yield subject, Content, HTML.format(body, @base)
        else # no <body> element
          yield subject, Content, HTML.format(n, @base)
        end
      end
    end
  end
end

class WebResource

  # RDF::Repository -> URI-indexed tree
  def treeFromGraph graph = nil
    graph ||= env[:repository]
    return {} unless graph

    tree = {}

    graph.each_triple{|s,p,o|
      s = s.to_s               # subject
      p = p.to_s               # predicate
      o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
      tree[s] ||= {'uri' => s} # insert subject
      tree[s][p] ||= []        # insert predicate
      if tree[s][p].class == Array
        tree[s][p].push o unless tree[s][p].member? o # insert in object-list
          else
            tree[s][p] = [tree[s][p],o] unless tree[s][p] == o # new object-list
      end}

    tree
  end

  module HTML

    # Graph -> HTML
    def htmlDocument graph=nil
      graph ||= env[:graph] = treeFromGraph
      qs = query_values || {}
      env[:colors] ||= {}
      env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (query ? ['?', query] : nil)].join unless path == '/' # pointer to container
      if env[:summary]                                                                                                  # pointer to unabridged content
        expanded = HTTP.qs qs.merge({'fullContent' => nil})
        env[:links][:full] = expanded
        expander = {_: :a, id: :expand, c: '&#11206;', href: expanded}
      end
      link = -> key, content { # render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url.R(env).href, id: key, class: :icon, c: content},
           "\n"]
        end}
      bgcolor = {401 => :orange, 403 => :yellow, 404 => :gray}[env[:origin_status]] || '#444'
      htmlGrep if local_node?
      groups = {}
      graph.map{|uri, resource| # group resources by type
        (resource[Type]||[:untyped]).map{|type|
          type = type.to_s
          type = MarkupMap[type] || type
          groups[type] ||= []
          groups[type].push resource }}

      HTML.render ["<!DOCTYPE html>\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[uri][Title].map(&:to_s).join ' ')} if graph.has_key?(uri) && graph[uri].has_key?(Title)),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             env[:links].map{|type, resource|
                               [{_: :link, rel: type, href: CGI.escapeHTML(resource.R(env).href)}, "\n"]}]}, "\n",
                        {_: :body, style: "background: repeating-linear-gradient(-45deg, #000, #000 .62em, #{bgcolor} .62em, #{bgcolor} 1em)",
                         c: [uri_toolbar, "\n",
                             link[:prev, '&#9664;'], "\n", link[:next, '&#9654;'], "\n",
                             groups.map{|type, resources|
                               if MarkupGroup.has_key? type
                                 MarkupGroup[type][resources, env]   # collection markup
                               else
                                 if env[:view] == 'table'
                                   HTML.tabular resources, env       # tabular view
                                 else
                                   resources.map{|resource|
                                     HTML.markup nil, resource, env} # singleton markup
                                 end
                               end},
                             expander,
                             {_: :script, c: SiteJS}]}]}]
    end

    # RDF -> Markup
    def self.markup type, v, env
      if [Abstract, Content, 'http://rdfs.org/sioc/ns#richContent'].member? type
        v
      elsif Markup[type] # markup lambda defined for type-argument
        Markup[type][v,env]
      elsif v.class == Hash # data
        types = (v[Type] || []).map{|t|
          MarkupMap[t.to_s] || t.to_s } # normalize types for renderer application
        seen = false
        [types.map{|type|
          if f = Markup[type] # markup lambda defined for type
            seen = true
            f[v,env]
          end},
         (keyval v, env unless seen)] # default key-value renderer
      elsif v.class == WebResource # resource-reference
        v
      else # renderer undefined
        CGI.escapeHTML v.to_s
      end
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
        render [{_: :a, href: x.uri, c: x.display_name}, ' ']
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end

    Markup[DC+'language'] = -> lang, env {
      {'de' => '🇩🇪',
       'en' => '🇬🇧',
       'fr' => '🇫🇷',
       'ja' => '🇯🇵',
      }[lang] || lang}

    MarkupGroup[Link] = -> links, env {
      links.map(&:R).group_by{|l|links.size > 8 && l.host && l.host.split('.')[-1] || nil}.map{|tld, links|
        [{class: :container,
          c: [({class: :head, _: :span, c: tld} if tld),
              {class: :body, c: links.group_by{|l|links.size > 25 ? ((l.host||'localhost').split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
                 ['<table><tr>',
                  ({_: :td, class: :head, c: alpha} if alpha),
                  {_: :td, class: :body,
                   c: {_: :table, class: :links,
                       c: links.group_by(&:host).map{|host, paths|
                         {_: :tr,
                          c: [{_: :td, class: :host,
                               c: host ? (name = ('//' + host).R.display_name
                                          color = env[:colors][name] ||= '#%06x' % (rand 16777216)
                                          {_: :a, href: '/' + host, c: name, style: "background-color: #{color}; color: black"}) : []},
                              {_: :td, c: paths.map{|path| Markup[Link][path,env]}}]}}}},
                  '</tr></table>']}}]}, '&nbsp;']}}

    Markup[Link] = -> ref, env {
      u = ref.to_s
      re = u.R env
      [{_: :a, href: re.href, class: :path, c: (re.path||'/')[0..79], title: u, id: 'link' + Digest::SHA2.hexdigest(rand.to_s)},
       " \n"]}

    Markup[Type] = -> t, env {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

  end
  include HTML
end
