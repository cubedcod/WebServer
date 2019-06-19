# coding: utf-8
class WebResource
  RDFmimes = /^(application|text)\/(atom|html|rss|turtle|xml)/
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
        #@doc = (input.respond_to?(:read) ? input : StringIO.new(input.to_s)).read.to_utf8
        @doc = input.respond_to?(:read) ? input.read : input
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
                crs.push name[1] if name && !(uri && uri[1].R.path.sub('/user/','/u/') == name[1])
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
        subject = ''
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
          graph << ::JSON::LD::API.toRdf(tree) rescue puts("JSON-LD read-error #{uri}")}
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
        unless (@base.host || '').match?(/(google|twitter).com/)
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
        text_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def text_triples
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
end
