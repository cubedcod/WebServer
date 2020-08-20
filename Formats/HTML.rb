# coding: utf-8
module Webize

  module HTML
    include WebResource::URIs

    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script" # CSS selector for script elements

    # set location references on local cache
    def self.cacherefs doc, env, serialize=true
      doc = Nokogiri::HTML.fragment doc if doc.class == String
      doc.css('a, form, iframe, img, link, script, source').map{|e| # ref element
        %w(action href src).map{|attr|              # ref attribute
          if e[attr]
            ref = e[attr].R                           # reference
            ref = env[:base].join ref unless ref.host # resolve host
            e[attr] = ref.R(env).href                 # cache location
          end}}

      doc.css('img[srcset]').map{|img|
        img['srcset'] = img['srcset'].split(',').map{|i|
          url, _ = i.split ' '
          url = env[:base].join(url).R env
          [url.href, _].join ' '
        }.join(',')}

      doc.css('style').map{|css|
        css.content = Webize::CSS.cacherefs css.content, env if css.content.match? /url\(/}

      serialize ? doc.to_html : doc
    end

    # clean HTML :: String
    def self.clean body, base=nil, serialize=true
      doc = Nokogiri::HTML.parse body.encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ') # parse ass Nokogiri doc
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
      clean_doc doc, base
      serialize ? doc.to_html : doc
    end

    # clean HTML :: Nokogiri
    def self.clean_doc doc, base=nil
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove # fonts and preload directives
      log = []
      doc.css("iframe, img, [type='image'], link, script, source").map{|s|
        text = s.inner_text     # inline gunk
        if s['type'] != 'application/json' && s['type'] != 'application/ld+json' && !text.match?(InitialState) && text.match?(GunkExec)
          log << "🚩 " + s.to_s.size.to_s + ' ' + (text.match(GunkExec)[2]||'')[0..42]
          s.remove
        end
        %w(href src).map{|attr| # referenced gunk
          if s[attr]
            src = s[attr].R
            if src.deny_domain?
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
      html = Nokogiri::HTML.fragment body rescue Nokogiri::HTML.fragment body.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
      html.css('iframe, style, link[rel="stylesheet"], ' + Scripts).remove
      clean_doc html

      # map images to <img> tag
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(/url\(['"]*([^\)'"]+)['"]*\)/).yield_self{|url|                                # CSS background-image -> img
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      html.css('amp-img').map{|amp| amp.add_child "<img src=\"#{amp['src']}\">"}                           # amp-img -> img
      html.css("div[class*='image'][data-src]").map{|div|div.add_child "<img src=\"#{div['data-src']}\">"} # div -> img
      html.css("figure[itemid]").map{|fig| fig.add_child "<img src=\"#{fig['itemid']}\">"}                 # figure -> img

      # identify <p> <pre> <ul> <ol>
      html.css('p').map{|e|   e.set_attribute 'id', 'p'   + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('pre').map{|e| e.set_attribute 'id', 'pre' + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('ul').map{|e|  e.set_attribute 'id', 'ul'  + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}
      html.css('ol').map{|e|  e.set_attribute 'id', 'ol'  + Digest::SHA2.hexdigest(rand.to_s)[0..3] unless e['id']}

      # inspect all nodes
      html.traverse{|e|
        e.attribute_nodes.map{|a|
          e.set_attribute 'src', a.value if SRCnotSRC.member? a.name    # map @src-like attributes to @src
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/)|| # strip attributes
                      %w(bgcolor class color height http-equiv layout ping role style tabindex target theme width).member?(a.name)}
        if e['href']; ref = (base.join e['href']).R                     # node has href and maybe identifier - add identifier for traversal if missing
          offsite = ref.host != base.host
          e.add_child " <span class='uri'>#{CGI.escapeHTML (offsite ? ref.uri.sub(/^https?:..(www.)?/,'') : (ref.path || '/'))[0..127]}</span> " # show URI in UI
          e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) unless e['id'] # add identifier
          css = [:uri]; css.push :path unless offsite                   # style as local or global reference
          e['href'] = ref.href                                          # resolve href
          e['class'] = css.join ' '                                     # add CSS style
        elsif e['id']                                                   # node has identifier but no href
          e.set_attribute 'class', 'identified'                         # style as identified node
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id'] unless e.name == 'p'}</span> " # add href to node
        end
        e['src'] = (base.join e['src']).R.href if e['src']}             # set media reference
      html.to_xhtml indent: 0
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
        @base = options[:base_uri]
        @doc = Nokogiri::HTML.parse(input.respond_to?(:read) ? input.read : input.to_s)
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
                @base.env[:links][:icon] ||= v.R if k.match? /^(fav)?icon?$/i
                @base.env[:feeds].push v if k == 'alternate' && ((m['type']&.match?(/atom|rss/)) || (v.path&.match?(/^\/feed\/?$/)))
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
        n.css('meta, [itemprop]').map{|m|
          if k = (m.attr("name") || m.attr("property") || m.attr("itemprop")) # predicate
            if v = (m.attr("content") || m.attr("href"))                      # object
              k = MetaMap[k] || k                               # normalize property-name
              case k
              when Abstract
                v = v.hrefs
              when /lytics/
                k = :drop
              else
                v = Webize::JSON.webizeString v
                v = @base.join v if v.class == WebResource || v.class == RDF::URI
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

        # RDFa + JSON-LD
        unless @base.to_s.match? /\/feed|polymer.*html/ # don't look for RDF in unpopulated templates
          embeds = RDF::Graph.new
          n.css('script[type="application/ld+json"]').map{|dataElement|
            embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}" # find JSON-LD triples
          RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"         # find RDFa triples
          embeds.each_triple{|s,p,o| # inspect  raw triple
            p = MetaMap[p.to_s] || p # map predicates
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/ # show unresolved property-names
            yield s, p, o unless p == :drop} # emit triple
        end

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

  module HTML

    # Graph -> HTML
    def htmlDocument graph=nil
      graph ||= env[:graph] = treeFromGraph
      qs = query_values || {}
      env[:view] ||= qs['view']
      env[:sort] ||= qs['sort']
      env[:colors] ||= {}
      env[:links][:up] = [File.dirname(env['REQUEST_PATH']), '/', (query ? ['?', query] : nil)].join unless path == '/' # pointer to container
      if env[:summary] || ((qs.has_key?('Q')||qs.has_key?('q')) && !qs.has_key?('fullContent'))      # pointer to unabbreviated form
        expanded = HTTP.qs qs.merge({'fullContent' => nil})
        env[:links][:full] = expanded
        expander = {_: :a, id: :expand, c: '&#11206;', href: expanded}
      end
      link = -> key, content { # render Link reference
        if url = env[:links] && env[:links][key]
          [{_: :a, href: url.R(env).href, id: key, class: :icon, c: content},
           "\n"]
        end}
      htmlGrep if local_node?

      HTML.render ["<!DOCTYPE html>\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :base, href: href},
                             {_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[uri][Title].map(&:to_s).join ' ')} if graph.has_key?(uri) && graph[uri].has_key?(Title)),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             env[:links].map{|type, resource|
                               [{_: :link, rel: type, href: CGI.escapeHTML(resource.R(env).href)}, "\n"]}]}, "\n",
                        {_: :body,
                         c: [uri_toolbar, "\n",
                             link[:prev, '&#9664;'], "\n",
                             link[:next, '&#9654;'], "\n",
                             if graph.empty?
                               HTML.keyval (Webize::JSON.webizeHash env), env
                             else
                               groups = {} # group resources by type
                               graph.map{|uri, resource|
                                 (resource[Type]||[:untyped]).map{|type|
                                   type = type.to_s
                                   groups[type] ||= []
                                   groups[type].push resource }}

                               # graph to markup
                               groups.map{|type, resources|
                                 type = MarkupMap[type] || type
                                 if MarkupGroup.has_key? type
                                   MarkupGroup[type][resources, env]   # typed-collection markup
                                 else
                                   if env[:view] == 'table'
                                     HTML.tabular resources, env       # tabular view
                                   else
                                     resources.map{|resource|
                                       HTML.markup nil, resource, env} # singleton-resource markup
                                   end
                                 end}
                             end, expander,
                             {_: :script, c: SiteJS}]}]}]
    end

    def uri_toolbar
      search_arg = [nil,'/'].member?(path) ? 'find' : 'q'
      qs = query_values || {}
      qs[search_arg] ||= ''
      bc = '' # breadcrumb trail
      favicon = ('//' + host  + '/favicon.ico').R
      icon = if env[:links][:icon]                                                                          # icon reference provided in upstream HTML
               if env[:links][:icon].path != favicon.path && !favicon.node.exist? && !favicon.node.symlink? # icon at non-default location?
                 FileUtils.ln_s (env[:links][:icon].node.relative_path_from favicon.node.dirname), favicon.node # link to default location
               end
               env[:links][:icon].node.exist? ? ('/' + env[:links][:icon].fsPath) : env[:links][:icon].href # referenced icon, at cache-location if on file
             elsif favicon.node.exist?                                                                      # site-icon exists at default location?
               '/' + favicon.fsPath                                                                         # site-icon
             else                                                                                           # daemon-icon
               '/favicon.ico'
             end
      {class: :toolbox,
       c: [({_: :a, id: :tabular, class: :icon, c: '↨', href: join(HTTP.qs(qs.merge({'view' => 'table', 'sort' => 'date'}))).R.href} unless qs['view'] == 'table'), "\n",
           ({_: :a, href: join(HTTP.qs(qs.merge({'notransform' => nil}))).R.href, c: '⚗️', id: :UI, class: :icon} unless local_node?), "\n",
           {_: :a, href: uri, c: '🔗', class: :icon, id: :directlink}, "\n",
           {_: :a, href: join('/').R.href, id: :host, c: {_: :img, src: icon}}, "\n",
           {class: :path,
            c: parts.map{|p| bc += '/' + p
              {_: :a, class: :breadcrumb, href: join(bc).R.href, c: [{_: :span, c: '/'}, (CGI.escapeHTML Rack::Utils.unescape p)], id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}}},
           ({_: :a, href: join(HTTP.qs(qs.merge({'dl' => env[:downloadable]}))).R.href, c: '&darr;', id: :download, class: :icon} if env.has_key? :downloadable), "\n",
           env[:feeds].map{|feed|
             {_: :a, href: feed.R.href, title: feed.path, class: :icon, c: FeedIcon}.update(feed.path.match?(/^\/feed\/?$/) ? {style: 'border: .1em solid orange; background-color: orange; margin-right: .1em'} : {})}, "\n",
           {_: :form, c: qs.map{|k,v|
              ["\n", {_: :input, name: k, value: v}.update(k == search_arg ? ((env[:searchable] && v.empty?) ? {autofocus: true} : {}) : {type: :hidden})]}}.update(env[:search_base] ? {action: join(env[:search_base]).R.href} : {}), "\n"]}
    end

    # {k => v} -> Markup
    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || (type.path && type.basename),
            c: ["\n",
                {_: :td, class: 'k',
                 c: Markup[Type][type, env]}, "\n",
                {_: :td, class: 'v',
                 c: k==Link ? MarkupGroup[Link][vs, env] : vs.map{|v|
                   [(markup k, v, env), ' ']}}]}, "\n"] unless k == 'uri' && vs[0] && vs[0].to_s.match?(/^_:/))}} # hide bnode internal-identifiers
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

  end
  include HTML
end
