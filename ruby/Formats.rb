# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

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
      content_type 'application/atom+xml',
                   extension: :atom,
                   aliases: %w(
                   application/rss+xml;q=0.9
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
                {DCe+'type' => Type,

                 Podcast+'author' => Creator,

                 Atom+'title'       => Title,
                 DCe+'subject'      => Title,
                 Media+'title'      => Title,
                 Podcast+'title'    => Title,
                 Podcast+'subtitle' => Title,
                 RSS+'title'        => Title,

                 Media+'description' => Abstract,
                 Atom+'summary'      => Abstract,

                 Atom+'content'                => Content,
                 RSS+'description'             => Content,
                 RSS+'encoded'                 => Content,
                 RSS+'modules/content/encoded' => Content,

                 RSS+'category'           => Label,
                 Podcast+'episodeType'    => Label,
                 Podcast+'keywords'       => Label,
                 YouTube+'videoId'        => Label,
                 Atom+'displaycategories' => Label,

                 RSS+'comments'               => Comments,
                 RSS+'modules/slash/comments' => SIOC+'num_replies',
                 Atom+'enclosure'             => SIOC+'attachment',
                 YouTube+'channelId'          => SIOC+'user_agent',
                 RSS+'source'                 => DC+'source',
                 Atom+'link'                  => DC+'link',

                }[p]||p, o }
      end

      def normalizeDates *f
        send(*f){|s,p,o|
          dateType = {'CreationDate' => true,
                      'Date' => true,
                      RSS+'pubDate' => true,
                      Date => true,
                      DCe+'date' => true,
                      Atom+'published' => true,
                      Atom+'updated' => true}[p]
          if dateType
            if !o.empty?
              yield s, Date, Time.parse(o).utc.iso8601
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
            yield u, Type, BlogPost.R

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
              elsif [Atom+'author', RSS+'author', RSS+'creator', DCe+'creator'].member? p
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
        subject = @base
        n = Nokogiri::HTML.parse @doc # parse HTML

        # triplr host-binding
        if hostTriples = WebResource::Webize::Triplr[:HTML][@base.host]
          @base.send hostTriples, n, &f
        end

        # JSON-LD
        graph = RDF::Graph.new
        n.css('script[type="application/ld+json"]').map{|json|
          tree = begin
                   ::JSON.parse json.inner_text
                 rescue
                   puts "JSON parse failed: #{json.inner_text}"
                   {}
                 end
          graph << ::JSON::LD::API.toRdf(tree) rescue puts("JSON-LD read-error on #{@base}")}
        graph.each_triple{|s,p,o|yield s, p, o}

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
                'twitter:creator' => Twitter,
                'twitter:description' => Abstract,
                'twitter:image' => Image,
                'twitter:image:src' => Image,
                'twitter:site' => Twitter,
                'twitter:title' => Title,
                'viewport' => :drop,
              }[k] || ('#' + k.gsub(' ','_'))

              case k
              when /lytics/
                k = :drop
              when Twitter
                v = (Twitter + '/' + v.sub(/^@/,'')).R
              when Abstract
                v = v.hrefs
              else
                v = HTML.webizeString v
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
                yield subject, Content, HTML.clean(content.inner_html)
              end}
            [*BasicGunk,*Gunk].map{|selector|
              body.css(selector).map{|sel|
                sel.remove }} # strip elements
            yield subject, Content, HTML.clean(body.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
          else
            puts "no <body> found in HTML #{@base}"
            n.css('head').remove
            yield subject, Content, HTML.clean(n.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
          end
        end
      end
    end
  end
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
        yield e, Identifier, id # Message-ID
        yield e, Type, Email.R

        # HTML
        htmlFiles, parts = m.all_parts.push(m).partition{|p|p.mime_type=='text/html'}
        htmlCount = 0
        htmlFiles.map{|p| # HTML file
          html = srcDir + "#{htmlCount}.html"  # file location
          yield e, DC+'hasFormat', html        # file pointer
          unless html.e
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
                HTML.render({_: :pre,
                             c: p.decoded.to_utf8.lines.to_a.map{|l| # split lines
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
                               end}.compact.intersperse("\n")})} # join lines

        # recursive contained messages: digests, forwards, archives
        parts.select{|p|p.mime_type=='message/rfc822'}.map{|m|
          content = m.body.decoded                   # decode message
          f = srcDir + content.sha2 + '.inlined.eml' # message location
          f.writeFile content if !f.e                # store message
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
                srcFile.link entry unless entry.e} # link if missing
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
              if !rel.e # link missing
                if destFile.e # link
                  destFile.link rel
                else # referenced file may appear later on
                  destFile.ln_s rel unless rel.symlink?
                end
              end
              srcFile.link rev if !rev.e}}}

        # attachments
        m.attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p| # decodability check
          name = p.filename.do{|f|f.to_utf8.do{|f|!f.empty? && f}} ||                           # explicit name
                 (rand.to_s.sha2 + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generated name
          file = srcDir + name                     # file location
          unless file.e
            file.writeFile p.body.decoded # store
            puts "FILE #{file}" if @verbose
          end
          yield e, SIOC+'attachment', file         # file pointer
          if p.main_type=='image'                  # image attachments
            yield e, Image, file                   # image link represented in RDF
            yield e, Content,                      # image link represented in HTML
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
=begin
URI-list
    def triplrUriList addHost = false
      base = stripDoc
      name = base.basename

      # containing file
      yield base.uri, Type, Container.R
      yield base.uri, Title, name
      prefix = addHost ? "https://#{name}/" : ''

      # resources
      lines.map{|line|
        t = line.chomp.split ' '
        unless t.empty?
          uri = prefix + t[0]
          resource = uri.R
          title = t[1..-1].join ' ' if t.size > 1
          yield uri, Title, title if title
          alpha = resource.host && resource.host.sub(/^www\./,'')[0] || ''
          container = base.uri + '#' + alpha
          yield container, Type, Container.R
          yield container, Title, alpha
          yield container, Contains, resource
        end}
    end
=end
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
