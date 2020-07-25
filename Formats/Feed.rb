# coding: utf-8
module Webize
  module Feed
    class Format < RDF::Format
      content_type 'application/rss+xml',
                   extensions: [:atom, :rss, :rss2],
                   aliases: %w(
                   application/atom+xml;q=0.8
                   application/x-rss+xml;q=0.2
                   application/xml;q=0.2
                   text/xml;q=0.2)

      content_encoding 'utf-8'

      reader { Reader }

      def self.symbols
        [:atom, :feed, :rss]
      end
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
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
                                                                                                              Webize::HTML.format o, @base
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
              if href = a.attr('href')
                # resolve URIs
                link = subject.join href
                re = link.R
                a.set_attribute 'href', link
                # emit hyperlinks as RDF
                if re.path && %w{gif jpeg jpg png webp}.member?(re.ext.downcase)
                  yield s, Image, re
                elsif re.path && (%w{mp4 webm}.member? re.ext.downcase) || (re.host && re.host.match(/v.redd.it|vimeo|youtu/))
                  yield s, Video, re
                elsif re != subject
                  yield s, DC+'link', re
                end
              end}

            # <img>
            content.css('img').map{|i|
              if src = i.attr('src')
                src = subject.join src
                i.set_attribute 'src', src
                yield s, Image, src.R
              end}

            # <iframe>
            content.css('iframe').map{|i|
              if src = i.attr('src')
                src = src.R
                if src.host && src.host.match(/youtu/)
                  id = src.parts[-1]
                  yield s, Video, ('https://www.youtube.com/watch?v='+id).R
                end
              end}

            # full HTML content
            yield s, p, content.to_xhtml
          else
            yield s, p, o
          end }
      end

      def normalizePredicates *f
        send(*f){|s,p,o|
          p = MetaMap[p] || p
          puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/
          yield s, p, o unless p == :drop}
      end

      def normalizeDates *f
        send(*f){|s,p,o|
          dateType = {'CreationDate' => true,
                      'Date' => true,
                      RSS+'pubDate' => true,
                      Date => true,
                      'http://purl.org/dc/elements/1.1/date' => true,
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
        reRDFabout = /about=["']?([^'">\s]+)/         # RDF @about
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
          u = (attrs && attrs.match(reRDFabout) ||
               inner.match(reLink) ||
               inner.match(reLinkCData) ||
               inner.match(reLinkHref) ||
               inner.match(reLinkRel) ||
               inner.match(reId)).yield_self{|capture|
            capture && capture[1]}

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
              if url = e[1].match(reSrc)
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
                      Atom + rel
                    end
                yield u,p,o unless resource == o
              end}

            # process XML elements
            inner.gsub(reGroup,'').scan(reElement){|e|
              p = (x[e[0] && e[0].chop]||RSS) + e[1] # attribute URI
              if [Atom+'id', RSS+'link', RSS+'guid', Atom+'link'].member? p
              # subject URI candidates
              elsif [Atom+'author', RSS+'author', RSS+'creator', 'http://purl.org/dc/elements/1.1/creator'].member? p
                # creators
                crs = []
                # XML name + URI
                uri = e[3].match /<uri>([^<]+)</
                name = e[3].match /<name>([^<]+)</
                crs.push uri[1].R if uri
                crs.push name[1] if name && !(uri && (uri[1].R.path||'/').sub('/user/','/u/') == name[1])
                unless name || uri
                  crs.push e[3].yield_self{|o|
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
                yield u, p, e[3].yield_self{|o|
                  case o
                  when isCDATA
                    o.sub reCDATA, '\1'
                  when /</m
                    o
                  else
                    CGI.unescapeHTML o
                  end
                }.yield_self{|o|
                  o.match(isURL) ? o.R : o }
              end
            }
          end}
      end
    end
  end
end
class WebResource
  module HTML

    def Chan doc
      #puts "chan  doc at  #{uri}"

      doc.css('.post, .postCell').map{|post|
        num = post.css('a.linkSelf, a.post_no, .postNum a')[0]

        subject = join(num ? num['href'] : ('#' + (post['id'] || (Digest::SHA2.hexdigest post.to_s))))

        graph = ['https://', subject.host, subject.path.sub(/\.html$/, ''), '/', subject.fragment].join.R

        yield subject, Type, Post.R, graph

        post.css('time, .dateTime').map{|date|
          yield subject, Date,
                (date['datetime'] || Time.at((date['data-utc'] ||
                                              date['unixtime']).to_i).iso8601), graph }

        post.css('.labelCreated').map{|created| yield subject, Date, Chronic.parse(created.inner_text).iso8601, graph}

        post.css('.name, .post_author').map{|name| yield subject, Creator, name.inner_text, graph}

        post.css('.post_title, .subject, .title').map{|subj| yield subject, Title, subj.inner_text, graph }

        post.css('.body, .divMessage, .postMessage, .text').map{|msg| yield subject, Content, msg, graph }

        post.css('.fileThumb, .imgLink').map{|a| yield subject, Image, (join a['href']), graph if a['href'] }

        post.css('.post_image, .post-image').map{|img| yield subject, Image, (join img.parent['href']), graph}

        post.css('[href$="mp4"], [href$="webm"]').map{|a| yield subject, Video, (join a['href']), graph}

        post.remove }
    end

    def feedDocument
      HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                   {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                    c: [{_: :id, c: uri},
                        {_: :title, c: uri},
                        {_: :link, rel: :self, href: uri},
                        {_: :updated, c: Time.now.iso8601},
                        treeFromGraph.map{|u,d|
                          {_: :entry,
                           c: [{_: :id, c: u}, {_: :link, href: u},
                               d[Date] ? {_: :updated, c: d[Date][0]} : nil,
                               d[Title] ? {_: :title, c: d[Title]} : nil,
                               d[Creator] ? {_: :author, c: d[Creator][0]} : nil,
                               {_: :content, type: :xhtml,
                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                    c: d[Content]}}]}}]}]
    end

    def HFeed doc
      doc.css('.entry').map{|post|
        if info = post.css('.status__info > a')[0]

          subject = graph = info['href'].R

          yield subject, Type, Post.R, graph

          post.css('.p-author').map{|author|
            author.css('a').map{|a|
              yield subject, Creator, a['href'].R, graph}
            yield subject, Creator, author.inner_text, graph}

          post.css('time').map{|date|
            yield subject, Date, date['datetime'], graph }

          post.css('.e-content').map{|msg|
            yield subject, Content, Webize::HTML.format(msg.inner_html, self), graph }

          post.css('img').map{|img|
            yield subject, Image, img['src'].R, graph }

          post.remove

        end}
    end

    Markup[Title] = -> title, env {
      if title.class == String
        {_: :h3, class: :title, c: CGI.escapeHTML(title)}
      end}

    Markup['http://purl.org/dc/terms/created'] = Markup['http://purl.org/dc/terms/modified'] = Markup[Date] = -> date, env {
      {_: :a, class: :date, c: date, href: 'http://' + (ENV['HOSTNAME'] || 'localhost') + ':8000/' + date[0..13].gsub(/[-T:]/,'/')}}

    Markup[Creator] = Markup[To] = Markup['http://xmlns.com/foaf/0.1/maker'] = -> c, env {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R env
        basename = u.basename if u.path
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        avatar = nil
        {_: :a, href: u.href,
         id: 'a' + Digest::SHA2.hexdigest(rand.to_s),
         class: avatar ? :avatar : :fromto,
         style: avatar ? '' : (env[:colors][name] ||= HTML.colorize),
         c: avatar ? {_: :img, class: :avatar, src: avatar} : name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post, env {
      post.delete Type
      uri = post.delete('uri') || ('#' + Digest::SHA2.hexdigest(rand.to_s))
      resource = uri.R env
      #puts :POST, [resource.host, resource.path].join(' '), [env[:base].host, env[:base].path].join(' ')

      titles = (post.delete(Title)||[]).map(&:to_s).map(&:strip).compact.-([""]).uniq
      abstracts = post.delete(Abstract) || []
      date = (post.delete(Date) || [])[0]
      from = post.delete(Creator) || []
      to = post.delete(To) || []
      images = post.delete(Image) || []
      links = post.delete(Link) || []
      content = post.delete(Content) || []
      htmlcontent = post.delete(SIOC + 'richContent') || []
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
      hasPointer = false

      local_id = if !resource.path || (resource.host == env[:base].host && resource.path == env[:base].path)
                   resource.fragment
                 else
                   uri_hash
                 end

      {class: :post, id: local_id,
       c: ["\n",
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               hasPointer = true
               [{_: :a,  id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :title, type: :node,
                 href: resource.href, c: CGI.escapeHTML(title)}, " \n"]
             end},
           ({_: :a, class: :id, type: :node, c: '🔗', href: resource.href, id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} unless hasPointer), "\n", # pointer
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
           (env[:cacherefs] ? [content, htmlcontent].flatten.compact.map{|c| Webize::HTML.cacherefs c, env} : [content, htmlcontent]).compact.join('<hr>'),
           MarkupGroup[Link][links, env],
           (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}}

  end
end
