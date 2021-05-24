# coding: utf-8
module Webize
  module HTML
    include WebResource::URIs

    CSSURL = /url\(['"]*([^\)'"]+)['"]*\)/
    CSSgunk = /font-face|url/

    # clean HTML document
    def self.clean doc, base
      log = -> type, content, filter {               # logger
        print type + " \e[38;5;8m" + content.to_s.gsub(/[\n\r\s\t]+/,' ').gsub(filter, "\e[38;5;48m\\0\e[38;5;8m") + "\e[0m "}

      doc = Nokogiri::HTML.parse doc.gsub /<\/?(noscript|wbr)[^>]*>/i,'' # strip <noscript> <wbr>
      doc.traverse{|e|                               # visit nodes

        if e['src']                                  # src attribute
          src = (base.join e['src']).R               # resolve locator
          if src.deny?
            puts "🚩 \e[38;5;196m#{src}\e[0m" if Verbose
            e.remove                                 # strip gunk reference in src attribute
          end
        end

        if (e.name=='link' && e['href']) || e['xlink:href'] # href attribute
          ref = (base.join (e['href'] || e['xlink:href'])).R # resolve location
          if ref.deny? || %w(dns-prefetch preconnect).member?(e['rel'])
            puts "🚩 \e[38;5;196m#{ref}\e[0m" if Verbose
            e.remove                                 # strip gunk reference in href attribute
          end
        end}

      doc.css('meta[content]').map{|meta|            # strip gunk reference in meta tag
        if meta['content'].match? /^https?:/
          meta.remove if meta['content'].R.deny?
        end}

      doc.css('script').map{|s|                      # visit scripts
        s.attribute_nodes.map{|a| (puts "🚩 \e[38;5;196m#{a.value}\e[0m" if Verbose; s.remove) if a.value.R.deny?}
                                                     # strip gunk reference in nonstandard src attribute
        text = s.inner_text                          # strip script gunk
        if !ScriptHosts.member?(base.host) && !base.env.has_key?(:scripts) && s['type'] != 'application/json' && s['type'] != 'application/ld+json' && !text.match?(/(Apollo|initial|preloaded)_*(data|state)/i) && text.match?(ScriptGunk) && !ENV.has_key?('JS')
          lines = text.split /[\n;]+/                # visit lines
          s.content = lines.grep_v(ScriptGunk).join ";\n" # strip gunked lines
          lines.grep(ScriptGunk).map{|l| log['✂️', l, ScriptGunk]} if Verbose
        end}

      doc.css('style').map{|node|                   # strip CSS gunk
        Webize::CSS.cleanNode node if node.inner_text.match? CSSgunk}

      doc.css('[style]').map{|node|
        Webize::CSS.cleanAttr node if node['style'].match? CSSgunk}

      dropnodes = "amp-ad, amp-consent, [class*='newsletter'], [class*='popup'], .player-unavailable"
      doc.css(dropnodes).map{|n| log['🧽', n, /amp-(ad|consent)|newsletter|popup/i]} if Verbose
      doc.css(dropnodes).remove                      # strip amp, newsletter, modal, popup gunk

      doc.css('[integrity]').map{|n|n.delete 'integrity'} # content is heavily modified, strip integrity signature

      doc.to_html                                    # serialize clean(er) doc
    end

    # format HTML per local preference
    def self.format html, base
      html = Nokogiri::HTML.fragment html if html.class == String

      # drop origin formatting and embeds
      html.css('iframe, script, style, link[rel="stylesheet"], link[type="text/javascript"], link[as="script"]').remove
      # a[href^="javascript"]

      # <img> mapping
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(CSSURL).yield_self{|url|                                # CSS background-image -> img
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp| amp.add_child "<img src=\"#{amp['src']}\">"}                           # amp-img -> img
      html.css("div[class*='image'][data-src]").map{|div|div.add_child "<img src=\"#{div['data-src']}\">"} # div -> img
      html.css("figure[itemid]").map{|fig| fig.add_child "<img src=\"#{fig['itemid']}\">"}                 # figure -> img
      html.css("figure > a[href]").map{|a| a.add_child "<img src=\"#{a['href']}\">"}                       # figure -> img
      html.css("slide").map{|s| s.add_child "<img src=\"#{s['original']}\" alt=\"#{s['caption']}\">"}      # slide -> img

      html.traverse{|e|                                              # visit nodes
        e.respond_to?(:attribute_nodes) && e.attribute_nodes.map{|a| # inspect attributes
          e.set_attribute 'src', a.value if SRCnotSRC.member? a.name # map alternative src attributes to @src
          e.set_attribute 'srcset', a.value if SRCSET.member? a.name # map alternative srcset attributes to @srcset
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w(bgcolor class color height http-equiv layout loading ping role style tabindex target theme width).member?(a.name)}
        if e['src']
          src = (base.join e['src']).R                               # resolve @src
          if src.deny?
            puts "🚩 \e[31;1m#{src}\e[0m" if Verbose
            e.remove
          else
            e['src'] = src.uri
          end
        end
        srcset e, base if e['srcset']                             # resolve @srcset
        if e['href']                                              # href attribute
          ref = (base.join e['href']).R                           # resolve @href
          ref.query = nil if ref.query&.match?(/utm[^a-z]/)       # deutmize query (tracker gunk)
          ref.fragment = nil if ref.fragment&.match?(/utm[^a-z]/) # deutmize fragment
          offsite = ref.host != base.host
          e.inner_html = [offsite ? ['<img src="//',ref.host,'/favicon.ico">'] : nil, # icon
                          e.inner_html,
                          e.inner_html == ref.uri ? nil : [' <span class="uri">',     # full URI
                                                           CGI.escapeHTML((offsite ? ref.uri.sub(/^https?:..(www.)?/,'') : (ref.path || '/'))[0..127]),
                                                           '</span> ']].join
          css = [:uri]
          css.push :path unless offsite                           # style as local or global reference
          css.push :blocked if ref.deny?                          # style as blocked resource
          e['href'] = ref.href                                    # update href to resolved location
          e['class'] = css.join ' '                               # add CSS style
          e['style'] = "#{offsite ? 'background-' : nil}color: #{HostColors[ref.host]}" if HostColors.has_key?(ref.host)
        elsif e['id']                                             # id attribute w/o href
          e.set_attribute 'class', 'identified'                   # style as identified node
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id'] unless e.name == 'p'}</span> " # add href to node
        end}

      html.to_html                                                # serialize
    end

    # rebase hrefs in HTML document
    def self.resolve_hrefs html, env, full=false
      return '' if !html || html.empty?                           # parse
      html = Nokogiri::HTML.send (full ? :parse : :fragment), (html.class==Array ? html.join : html)

      html.css('[src]').map{|i|                                   # @src
        i['src'] = env[:base].join(i['src']).R(env).href}

      html.css('[srcset]').map{|i|                                # @srcset
        srcset = i['srcset'].scan(SrcSetRegex).map{|ref, size| [ref.R(env).href, size].join ' '}.join(', ')
        i['srcset'] = srcset unless srcset.empty?}

      html.css('[href]').map{|a|
        a['href'] = env[:base].join(a['href']).R(env).href} # @href

      html.to_html                                                # serialize
    end

    class Format < RDF::Format
      content_type 'text/html', extensions: [:htm, :html]
      content_encoding 'utf-8'
      reader { Reader }
    end

    # HTML document -> RDF
    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @base.env[:links] ||= {}
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
        embeds = RDF::Graph.new # storage for embedded graphs
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
                yield subject, k, v unless k == :drop || v.R.deny?}
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

        # JSON (generic)
        n.css('script[type="application/json"], script[type="text/json"]').map{|json|
          Webize::JSON::Reader.new(json.inner_text.strip.sub(/^<!--/,'').sub(/-->$/,''), base_uri: @base).scanContent &f}

        # JSON (LD)
        n.css('script[type="application/ld+json"]').map{|dataElement|
          embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"   # JSON-LD triples

        # RDFa
        n.css('script').remove # we're done extracting RDF from scripts, RDFa::Reader recursively instantiates readers for scripts if they exist
        RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"           # RDFa triples

        # Microdata
        RDF::Reader.for(:microdata).new(@doc, base_uri: @base){|_| embeds << _ } rescue "Microdata read failure in #{@base}" # Microdata triples

        # emit triples from embed graphs
        embeds.each_triple{|s,p,o| # inspect  raw triple
          p = MetaMap[p.to_s] || p # map predicates
          puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # log unresolved property-names
          yield s, p, o, (['//', s.host, s.path].join.R if s.class == RDF::URI && s.host) unless p == :drop} # emit triple

        # <body>
        if body = n.css('body')[0]
          unless @base.local_node? || @base.env[:fullContent] # summarize to new content
            @base.env[:links][:down] = WebResource::HTTP.qs @base.env[:qs].merge({'fullContent' => nil})
            hashed_nodes = 'div, footer, h1,h2,h3, nav, p, section, span, ul, li'
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
    def htmlDocument graph = nil
      graph ||= env[:graph] = treeFromGraph                                                        # treeify graph
      env[:colors] ||= {}                                                                          # named color(s) container
      env[:links][:up] ||= (!path || path=='/') ? '//' + host.split('.')[1..-1].join('.') : [File.dirname(env['REQUEST_PATH']), '/', (query ? ['?', query] : nil)].join
      icon = ('//'+(host||'localhost:8000')+'/favicon.ico').R env                                  # well-known icon location
      if env[:links][:icon]                                                                        # icon reference in metadata
        env[:links][:icon] = env[:links][:icon].R env unless env[:links][:icon].class==WebResource # normalize reference
        if !env[:links][:icon].data? && env[:links][:icon].path != icon.path && !icon.node.exist? && !icon.node.symlink?
          FileUtils.mkdir_p File.dirname icon.fsPath                                               # unlinked well-known location
          FileUtils.ln_s (env[:links][:icon].node.relative_path_from icon.node.dirname), icon.node # link to well-known location
        end
      end
      env[:links][:icon] ||= icon.node.exist? ? icon : '//localhost:8000/favicon.ico'.R(env)       # default well-known icon
      bgcolor = {401 => :orange,403 => :yellow,404 => :gray,408 => '#f0c'}[env[:status]] || '#333' # background color
      htmlGrep if local_node?                                                                      # HTMLify grep results
      groups = {}                                                                                  # group(s) container
      graph.map{|uri, resource|                                                                    # group resources by type
        (resource[Type]||[:untyped]).map{|type|
          type = type.to_s
          type = MarkupMap[type] || type
          groups[type] ||= []
          groups[type].push resource }}

      link = -> key, content {                                                                     # lambda: render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url.R(env).href, id: key, class: :icon, c: content},
           "\n"]
        end}

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
                             groups.map{|type, resources|
                               if MarkupGroup.has_key? type
                                 MarkupGroup[type][resources, env]
                               elsif env[:view] == 'table'
                                 HTML.tabular resources, env
                               else
                                 resources.map{|r|HTML.markup nil, r, env}
                               end},
                             link[:prev, '&#9664;'], "\n",
                             env[:links][:down] ? {_: :a, id: :expand, c: '&#11206;', href: env[:links][:down]} : nil,
                             link[:next, '&#9654;'], "\n",
                             {_: :script, c: SiteJS}]}]}]
    end

    # arbitrary JSON -> Markup
    def self.markup type, v, env
      if [Abstract, Content, 'http://rdfs.org/sioc/ns#richContent'].member? type
        (env.has_key?(:proxy_href) && v.class==String) ? Webize::HTML.resolve_hrefs(v, env) : v
      elsif Markup[type] # renderer defined for type argument
        Markup[type][v,env]
      elsif v.class == Hash # RDF-in-JSON object
        types = (v[Type] || []).map{|t| # type defined in RDF
          MarkupMap[t.to_s] || t.to_s } # map to render type
        seen = false
        [types.map{|type|
          if f = Markup[type] # renderer defined for RDF type-tag
            seen = true
            f[v,env]
          end},
         (keyval v, env unless seen)] # default to key-value render
      elsif v.class == WebResource # resource reference
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

  end
  include HTML
end
