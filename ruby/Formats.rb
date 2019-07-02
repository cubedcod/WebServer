# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/
  module URIs
    BasicSlugs = %w{
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r reddit rss rssfeed
 sports source story
 t the threads topic tumblr
 uk utm www}
    FeedMIME = 'application/atom+xml'
  end
  module Calendar
    class Format < RDF::Format
      content_type 'text/calendar', :extension => :ics
      content_encoding 'utf-8'
      reader { WebResource::Calendar::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#textfile').R
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
        calendar_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def calendar_triples
        Icalendar::Calendar.parse(@doc).map{|cal|
          cal.events.map{|event|
            subject = event.url || ('#event'+rand.to_s.sha2)
            yield subject, Date, event.dtstart
            yield subject, Title, event.summary
            yield subject, Abstract, CGI.escapeHTML(event.description)
            yield subject, '#geo', event.geo if event.geo
            yield subject, '#location', event.location if event.location
          }}
      end
    end
  end
  module Feed
    class Format < RDF::Format
      content_type 'application/rss+xml',
                   extension: :rss,
                   aliases: %w(
                   application/atom+xml;q=0.8
                   application/xml;q=0.2
                   text/xml;q=0.2
                   )
      content_encoding 'utf-8'

      reader { WebResource::Feed::Reader }

      def self.symbols
        [:atom, :feed, :rss]
      end
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).to_utf8
        @base = options[:base_uri].R
        @host = @base.host
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
        scanContent(:normalizeDates, :normalizePredicates,:rawTriples){|s,p,o| # triples flow (left ← right) in filter stack
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal (if p == Content
                                                                                                              WebResource::HTML.clean o
                                                                                                             else
                                                                                                               o.gsub(/<[^>]*>/,' ')
                                                                                                              end)
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l), :graph_name => s.R)}
      end

      def scanContent *f
        send(*f){|s,p,o|
          if p==Content && o.class==String
            subject = s.R
            object = o.strip
            # wrap bare text-region in <p>
            o = object.match(/</) ? object : ('<p>'+object+'</p>')
            # parse HTML
            content = Nokogiri::HTML.fragment o

            # <a>
            content.css('a').map{|a|
              (a.attr 'href').do{|href|
                # resolve URIs
                link = subject.join href
                re = link.R
                a.set_attribute 'href', link
                # emit hyperlinks as RDF
                if %w{gif jpeg jpg png webp}.member? re.ext.downcase
                  yield s, Image, re
                elsif (%w{mp4 webm}.member? re.ext.downcase) || (re.host && re.host.match(/(vimeo|youtu)/))
                  yield s, Video, re
                elsif re != subject
                  yield s, DC+'link', re
                end }}

            # <img>
            content.css('img').map{|i|
              (i.attr 'src').do{|src|
                # TODO find reblogs with relative URIs in content and check RFCish specs on whether relURI base is resource or doc
                src = subject.join src
                i.set_attribute 'src', src
                yield s, Image, src.R}}

            # <iframe>
            content.css('iframe').map{|i|
              (i.attr 'src').do{|src|
                src = src.R
                if src.host && src.host.match(/youtu/)
                  id = src.parts[-1]
                  yield s, Video, ('https://www.youtube.com/watch?v='+id).R
                end }}

            # full HTML content
            yield s, p, content.to_xhtml
          else
            yield s, p, o
          end }
      end

      def normalizePredicates *f
        send(*f){|s,p,o|
          yield s,
                {DCelement+'type' => Type,

                 Podcast+'author' => Creator,

                 Atom+'title'        => Title,
                 DCelement+'subject' => Title,
                 Podcast+'subtitle'  => Title,
                 Podcast+'title'     => Title,
                 RSS+'title'         => Title,
                 'http://search.yahoo.com/mrss/title' => Title,

                 Atom+'summary'                             => Abstract,
                 'http://search.yahoo.com/mrss/description' => Abstract,

                 Atom+'content'                => Content,
                 RSS+'description'             => Content,
                 RSS+'encoded'                 => Content,
                 RSS+'modules/content/encoded' => Content,

                 Atom+'displaycategories' => Label,
                 Podcast+'episodeType'    => Label,
                 Podcast+'keywords'       => Label,
                 RSS+'category'           => Label,

                 Atom+'enclosure'             => SIOC+'attachment',
                 Atom+'link'                  => DC+'link',
                 RSS+'modules/slash/comments' => SIOC+'num_replies',
                 RSS+'source'                 => DC+'source',

                }[p]||p, o }
      end

      def normalizeDates *f
        send(*f){|s,p,o|
          dateType = {'CreationDate' => true,
                      'Date' => true,
                      RSS+'pubDate' => true,
                      Date => true,
                      DCelement+'date' => true,
                      Atom+'published' => true,
                      Atom+'updated' => true}[p]
          if dateType
            if !o.empty?
              yield s, Date, Time.parse(o).utc.iso8601 rescue nil
            end
          else
            yield s,p,o
          end
        }
      end

      def rawTriples
        # identifier-search regular expressions
        reRDF = /about=["']?([^'">\s]+)/              # RDF @about
        reLink = /<link>([^<]+)/                      # <link> element
        reLinkCData = /<link><\!\[CDATA\[([^\]]+)/    # <link> CDATA block
        reLinkHref = /<link[^>]+rel=["']?alternate["']?[^>]+href=["']?([^'">\s]+)/ # <link> @href @rel=alternate
        reLinkRel = /<link[^>]+href=["']?([^'">\s]+)/ # <link> @href
        reId = /<(?:gu)?id[^>]*>([^<]+)/              # <id> element
        isURL = /\A(\/|http)[\S]+\Z/                  # HTTP URI

        # XML (and/or SGML/XML-like) elements
        isCDATA = /^\s*<\!\[CDATA/m
        reCDATA = /^\s*<\!\[CDATA\[(.*?)\]\]>\s*$/m
        reElement = %r{<([a-z0-9]+:)?([a-z]+)([\s][^>]*)?>(.*?)</\1?\2>}mi
        reGroup = /<\/?media:group>/i
        reHead = /<(rdf|rss|feed)([^>]+)/i
        reItem = %r{<(?<ns>rss:|atom:)?(?<tag>item|entry)(?<attrs>[\s][^>]*)?>(?<inner>.*?)</\k<ns>?\k<tag>>}mi
        reMedia = %r{<(link|enclosure|media)([^>]+)>}mi
        reSrc = /(href|url|src)=['"]?([^'">\s]+)/
        reRel = /rel=['"]?([^'">\s]+)/
        reXMLns = /xmlns:?([a-z0-9]+)?=["']?([^'">\s]+)/

        # XML-namespace lookup table
        x = {}
        head = @doc.match(reHead)
        head && head[2] && head[2].scan(reXMLns){|m|
          prefix = m[0]
          base = m[1]
          base = base + '#' unless %w{/ #}.member? base [-1]
          x[prefix] = base}

        # scan document
        @doc.scan(reItem){|m|
          attrs = m[2]
          inner = m[3]
          # identifier search
          u = (attrs.do{|a|a.match(reRDF)} ||
               inner.match(reLink) ||
               inner.match(reLinkCData) ||
               inner.match(reLinkHref) ||
               inner.match(reLinkRel) ||
               inner.match(reId)).do{|s|s[1]}

          puts "post-identifier search failed #{@base}" unless u
          if u # identifier found
            # resolve URI
            u = @base.join(u).to_s unless u.match /^http/
            resource = u.R

            # type-tag
            yield u, Type, (SIOC + 'BlogPost').R

            # post target (blog, re-blog)
            blogs = [resource.join('/')]
            blogs.push @base.join('/') if @host && @host != resource.host # re-blog
            blogs.map{|blog|
              forum = if resource.host&.match /reddit.com$/
                        ('https://www.reddit.com/' + resource.parts[0..1].join('/')).R
                      else
                        blog
                      end
              yield u, WebResource::To, forum}

            # media links
            inner.scan(reMedia){|e|
              e[1].match(reSrc).do{|url|
                rel = e[1].match reRel
                rel = rel ? rel[1] : 'link'
                o = (@base.join url[2]).R
                p = case o.ext.downcase
                    when 'jpg'
                      WebResource::Image
                    when 'jpeg'
                      WebResource::Image
                    when 'png'
                      WebResource::Image
                    else
                      WebResource::Atom + rel
                    end
                yield u,p,o unless resource == o}}

            # process XML elements
            inner.gsub(reGroup,'').scan(reElement){|e|
              p = (x[e[0] && e[0].chop]||WebResource::RSS) + e[1] # attribute URI
              if [Atom+'id', RSS+'link', RSS+'guid', Atom+'link'].member? p
              # subject URI candidates
              elsif [Atom+'author', RSS+'author', RSS+'creator', DCelement+'creator'].member? p
                # creators
                crs = []
                # XML name + URI
                uri = e[3].match /<uri>([^<]+)</
                name = e[3].match /<name>([^<]+)</
                crs.push uri[1].R if uri
                crs.push name[1] if name && !(uri && (uri[1].R.path||'/').sub('/user/','/u/') == name[1])
                unless name || uri
                  crs.push e[3].do{|o|
                    case o
                    when isURL
                      o.R
                    when isCDATA
                      o.sub reCDATA, '\1'
                    else
                      o
                    end}
                end
                # author(s) -> RDF
                crs.map{|cr|yield u, Creator, cr}
              else # element -> RDF
                yield u,p,e[3].do{|o|
                  case o
                  when isCDATA
                    o.sub reCDATA, '\1'
                  when /</m
                    o
                  else
                    CGI.unescapeHTML o
                  end
                }.do{|o|
                  o.match(isURL) ? o.R : o }
              end
            }
          end}
      end
    end
  end
  module GIF
    class Format < RDF::Format
      content_type 'image/gif', :extension => :gif
      content_encoding 'utf-8'
      reader { WebResource::GIF::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil #puts("EXIF read failed on #{@subject}")
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
      end
    end
  end
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
        node['style'].match(/url\('([^']+)'/).do{|url|
          node.add_child "<img src=\"#{url[1]}\">"}}

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
        @r[:links][key].do{|uri|
          [uri.R.data({id: key, label: displayname}),
           "\n"]}}


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
                             *@r[:links].do{|links|
                               links.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}}
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
                               HTML.keyval (HTML.webizeHash @r), @r # 404
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
        (r[Content]||r[Abstract]).justArray.map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).do{|lines|
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
                   value k, v, env}.intersperse(' ')}]}, "\n"] unless k=='uri' && vs.justArray[0].to_s.match?(/^_:/))}}
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
      if c.respond_to? :uri
        u = c.R

        name = u.fragment ||
               u.basename.do{|b| ['','/'].member?(b) ? false : b} ||
               u.host.do{|h|h.sub(/\.com$/,'')} ||
               'user'

        color = env[:colors][name] ||= HTML.colorize
        {_: :a, id: 'a'+rand.to_s.sha2, class: :creator, style: color, href: uris.justArray[0] || c.uri, c: name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post , env {
      uri = post.uri.justArray[0]
      post.delete 'uri'
      post.delete Type
      titles = post.delete(Title).justArray.map(&:to_s).map(&:strip).uniq
      date = post.delete(Date).justArray[0]
      from = post.delete(From).justArray
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
      if image.respond_to? :uri
        img = image.R
        if env[:images] && env[:images][img.uri]
        # deduplicate
        else
          env[:images] ||= {}
          env[:images][img.uri] = true
          {class: :thumb, c: {_: :a, href: img.uri, c: {_: :img, src: img.uri}}}
        end
      else
        CGI.escapeHTML image.to_s
      end}

    Markup[Video] = -> video,env {
      video = video.R
      if env[:images][video.uri]
      else
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
                               d[Date].do{|d|   {_: :updated, c: d[0]}},
                               d[Title].do{|t|  {_: :title,   c: t}},
                               d[Creator].do{|c|{_: :author,  c: c[0]}},
                               {_: :content, type: :xhtml,
                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                    c: d[Content]}}]}}]}]
    end

    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Content, DC+'hasFormat', DC+'identifier', Image, Mtime, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
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
                         {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :id, c: '☚'}
                       else
                         titles[title] = true
                         {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :title,
                          c: [(CGI.escapeHTML title), ' ',
                              {_: :span, class: :uri, c: CGI.escapeHTML(resource.uri)}, ' ']}
                       end}
                   else
                     {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :id, c: '&#x1f517;'}
                   end
                 else
                   resource[k].justArray.map{|v|value k, v, env }
                  end}}},
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Image].justArray.map{|i|{style: 'max-width: 20em', c: Markup[Image][i,env]}},
                                resource[Content]]}} if (resource[Content] || resource[Image]) && !env[:query].has_key?('head'))]}]}
    end

    def self.tree t, env, name=nil
      url = t[:RDF].uri if t[:RDF]
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
        if (types.member? Post) || (types.member? SIOC+'BlogPost') || (types.member? Email)
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
      reader { WebResource::HTML::Reader }
    end

    class Reader < RDF::Reader
      include URIs
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
        if hostTriples = WebResource::Webize::Triplr[:HTML][@base.host]
          @base.send hostTriples, n, &f
        end

        # JSON-LD
        n.css('script[type="application/ld+json"]').map{|json|
          tree = begin
                   ::JSON.parse json.inner_text
                 rescue
                   puts "JSON parse failed: #{json.inner_text}"
                   {}
                 end
          embeds << ::JSON::LD::API.toRdf(tree) rescue puts("JSON-LD read-error on #{@base}")}

        # RDFa
        RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ }

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
          m.attr("rel").do{|k| # predicate
            m.attr("href").do{|v| # object
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
            }}}

        # <meta>
        n.css('head meta').map{|m|
          (m.attr("name") || m.attr("property")).do{|k| # predicate
            m.attr("content").do{|v| # object

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
            }}}

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
  include HTML
  module JPEG
    class Format < RDF::Format
      content_type 'image/jpeg', :extension => :jpg
      content_encoding 'utf-8'
      reader { WebResource::JPEG::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil #puts("EXIF read failed on #{@subject}")
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject,
                                     p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples
        yield Image, @subject
        [:ifd0, :ifd1, :exif, :gps].map{|fields|
          @img[fields].map{|k,v|
            if k == :date_time
              yield Date, v.sub(':','-').sub(':','-').to_time.iso8601
            else
              yield ('http://www.w3.org/2003/12/exif/ns#' + k.to_s), v.to_s.to_utf8
            end
          }} if @img
      end
      
    end
  end
  module JSON
    class Format < RDF::Format
      content_type 'application/json', :extension => :json
      content_encoding 'utf-8'
      reader { WebResource::JSON::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil #puts("EXIF read failed on #{@subject}")
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

      end

    end
  end
  module PNG
    class Format < RDF::Format
      content_type 'image/png', :extension => :png
      content_encoding 'utf-8'
      reader { WebResource::PNG::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        #@img = Exif::Data.new(input.respond_to?(:read) ? input.read : input)
        @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
  module Mail
    class Format < RDF::Format
      content_type 'message/rfc822', :extension => :eml
      content_encoding 'utf-8'
      reader { WebResource::Mail::Reader }
      def self.symbols
        [:mail]
      end
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#textfile').R
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
        mail_triples{|s,p,o|
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => s.R)}
      end
      def mail_triples &b; @verbose = true
        m = ::Mail.new @doc
        unless m
          puts "mail parse failed:", @doc
          return
        end
        # Message-ID
        id = m.message_id || m.resent_message_id || rand.to_s.sha2
        puts "\n MID #{id}" if @verbose

        # Message URI
        msgURI = -> id {
          h = id.sha2
          ['', 'msg', h[0], h[1], h[2], id.gsub(/[^a-zA-Z0-9]+/,'.')[0..96], '#this'].join('/').R}
        resource = msgURI[id]
        e = resource.uri
        puts " URI #{resource}" if @verbose

        srcDir = resource.path.R      # message dir
        srcFile = srcDir + 'this.eml' # message path
        unless srcFile.exist?
          srcFile.writeFile @doc # store in canonical-location
          puts "LINK #{srcFile}" if @verbose
        end
        yield e, DC + 'identifier', id # Message-ID
        yield e, Type, Email.R

        # HTML
        htmlFiles, parts = m.all_parts.push(m).partition{|p|p.mime_type=='text/html'}
        htmlCount = 0
        htmlFiles.map{|p| # HTML file
          html = srcDir + "#{htmlCount}.html"  # file location
          yield e, DC+'hasFormat', html        # file pointer
          unless html.exist?
            html.writeFile p.decoded  # store HTML email
            puts "HTML #{html}" if @verbose
          end
          htmlCount += 1 } # increment count

        # plaintext
        parts.select{|p|
          (!p.mime_type || p.mime_type == 'text/plain') && # text parts
            ::Mail::Encodings.defined?(p.body.encoding)      # decodable?
        }.map{|p|
          yield e, Content,
                HTML.render(p.decoded.to_utf8.lines.to_a.map{|l| # split lines
                              l = l.chomp # strip any remaining [\n\r]
                              if qp = l.match(/^((\s*[>|]\s*)+)(.*)/) # quoted line
                                depth = (qp[1].scan /[>|]/).size # > count
                                if qp[3].empty? # drop blank quotes
                                  nil
                                else # wrap quotes in <span>
                                  indent = "<span name='quote#{depth}'>&gt;</span>"
                                  {_: :span, class: :quote,
                                   c: [indent * depth,' ',
                                       {_: :span, class: :quoted,
                                        c: qp[3].hrefs{|p,o|
                                          yield e, p, o }}]}
                                end
                              else # fresh line
                                [l.hrefs{|p, o|
                                   yield e, p, o}]
                              end})} # join lines

        # recursive contained messages: digests, forwards, archives
        parts.select{|p|p.mime_type=='message/rfc822'}.map{|m|
          content = m.body.decoded                   # decode message
          f = srcDir + content.sha2 + '.inlined.eml' # message location
          f.writeFile content if !f.exist?           # store message
          f.triplrMail &b} # triplr on contained message

        # From
        from = []
        m.from.do{|f|
          f.justArray.compact.map{|f|
            noms = f.split ' '
            if noms.size > 2 && noms[1] == 'at'
              f = "#{noms[0]}@#{noms[2]}"
            end
            puts "FROM #{f}" if @verbose 
            from.push f.to_utf8.downcase}} # queue address for indexing + triple-emitting
        m[:from].do{|fr|
          fr.addrs.map{|a|
            name = a.display_name || a.name # human-readable name
            yield e, Creator, name
            puts "NAME #{name}" if @verbose
          } if fr.respond_to? :addrs}
        m['X-Mailer'].do{|m|
          yield e, SIOC+'user_agent', m.to_s
          puts " MLR #{m}" if @verbose
        }

        # To
        to = []
        %w{to cc bcc resent_to}.map{|p|      # recipient fields
          m.send(p).justArray.map{|r|        # recipient
            puts "  TO #{r}" if @verbose
            to.push r.to_utf8.downcase }}    # queue for indexing
        m['X-BeenThere'].justArray.map{|r|to.push r.to_s} # anti-loop recipient
        m['List-Id'].do{|name|yield e, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,'')} # mailinglist name

        # Subject
        subject = nil
        m.subject.do{|s|
          subject = s.to_utf8
          subject.scan(/\[[^\]]+\]/){|l| yield e, Label, l[1..-2]}
          yield e, Title, subject}

        # Date
        date = m.date || Time.now rescue Time.now
        date = date.to_time.utc
        dstr = date.iso8601
        yield e, Date, dstr
        dpath = '/' + dstr[0..6].gsub('-','/') + '/msg/' # month
        puts "DATE #{date}\nSUBJ #{subject}" if @verbose && subject

        # index addresses
        [*from,*to].map{|addr|
          user, domain = addr.split '@'
          if user && domain
            apath = dpath + domain + '/' + user # address
            yield e, (from.member? addr) ? Creator : To, apath.R # To/From triple
            if subject
              slug = subject.scan(/[\w]+/).map(&:downcase).uniq.join('.')[0..63]
              mpath = apath + '.' + dstr[8..-1].gsub(/[^0-9]+/,'.') + slug # (month,addr,title) path
              [(mpath + (mpath[-1] == '.' ? '' : '.')  + 'eml').R, # monthdir entry
               ('mail/cur/' + id.sha2 + '.eml').R].map{|entry|     # maildir entry
                srcFile.link entry unless entry.exist?} # link if missing
            end
          end
        }

        # index bidirectional refs
        %w{in_reply_to references}.map{|ref|
          m.send(ref).do{|rs|
            rs.justArray.map{|r|
              dest = msgURI[r]
              yield e, SIOC+'reply_of', dest
              destDir = dest.path.R
              destDir.mkdir
              destFile = destDir + 'this.eml'
              # bidirectional reference link
              rev = destDir + id.sha2 + '.eml'
              rel = srcDir + r.sha2 + '.eml'
              if !rel.exist? # link missing
                if destFile.exist? # link
                  destFile.link rel
                else # referenced file may appear later on
                  destFile.ln_s rel unless rel.symlink?
                end
              end
              srcFile.link rev if !rev.exist?}}}

        # attachments
        m.attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p| # decodability check
          name = p.filename.do{|f|f.to_utf8.do{|f|!f.empty? && f}} ||                           # explicit name
                 (rand.to_s.sha2 + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generated name
          file = srcDir + name                     # file location
          unless file.exist?
            file.writeFile p.body.decoded # store attachment
            puts "FILE #{file}" if @verbose
          end
          yield e, SIOC+'attachment', file         # file pointer
          if p.main_type=='image'                  # image attachments
            yield e, Image, file                   # image link in RDF
            yield e, Content,                      # image link in HTML
                  HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}) # render HTML
          end }
      end

    end
  end
  module Markdown
    class Format < RDF::Format
      content_type 'text/markdown', :extension => :md
      content_encoding 'utf-8'
      reader { WebResource::Markdown::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#textfile').R
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
        markdown_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def markdown_triples
        yield @subject, Content, ::Redcarpet::Markdown.new(::Redcarpet::Render::Pygment, fenced_code_blocks: true).render(@doc)
      end
    end
  end
  module Plaintext
    class Format < RDF::Format
      content_type 'text/plain', :extension => :txt
      content_encoding 'utf-8'
      reader { WebResource::Plaintext::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#textfile').R
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
        text_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def text_triples
        yield @subject, Content, HTML.render({_: :pre, style: 'white-space: pre-wrap',
                                              c: @doc.hrefs{|p,o| # hypertextize
                                                # yield detected links to consumer
                                                yield @subject, p, o
                                                yield o, Type, Resource.R}})
      end
    end
  end
  module WebP
    class Format < RDF::Format
      content_type 'image/webp', :extension => :webp
      content_encoding 'utf-8'
      reader { WebResource::WebP::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        #@img = Exif::Data.new(input.respond_to?(:read) ? input.read : input)
        @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
  module URIs
    Extensions = RDF::Format.file_extensions.invert
  end
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
