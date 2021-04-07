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
                                                                                                              Webize::HTML.format o, @base
                                                                                                             else
                                                                                                               o.gsub(/<[^>]*>/,' ')
                                                                                                              end)
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l), :graph_name => s.R)}
      end

      def scanContent *f
        send(*f){|subject, p, o|
          if p==Content && o.class==String
            content = Nokogiri::HTML.fragment o
            # <a>
            content.css('a').map{|a|
              if href = a.attr('href')
                # resolve URIs
                link = subject.join href
                a.set_attribute 'href', link.to_s
                # emit hyperlinks as RDF
                if link.path && %w{gif jpeg jpg png webp}.member?(link.R.ext.downcase)
                  yield subject, Image, link
                elsif link.path && (%w{mp4 webm}.member? link.R.ext.downcase) || (link.host && link.host.match(/v.redd.it|vimeo|youtu/))
                  yield subject, Video, link
                elsif link != subject
                  yield subject, DC+'link', link
                end
              end}

            # <img>
            content.css('img').map{|i|
              if src = i.attr('src')
                src = subject.join src
                i.set_attribute 'src', src.to_s
                yield subject, Image, src
              end}

            # <iframe>
            content.css('iframe').map{|i|
              if src = i.attr('src')
                src = subject.join src
                if src.host && src.host.match(/youtu/)
                  id = src.R.parts[-1]
                  yield subject, Video, ('https://www.youtube.com/watch?v=' + id).R
                end
              end}
            yield subject, p, content.to_xhtml
          else
            yield subject, p, o
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
        reOrigLink = /<feedburner:origLink>([^<]+)/   # <feedburner:origLink> element
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
          if id = (attrs && attrs.match(reRDFabout) ||
                   inner.match(reOrigLink) ||
                   inner.match(reLink) ||
                   inner.match(reLinkCData) ||
                   inner.match(reLinkHref) ||
                   inner.match(reLinkRel) ||
                   inner.match(reId)).yield_self{|capture|
               capture && capture[1]}

            subject = @base.join id
            subject.query = nil if subject.query&.match?(/utm[^a-z]/)
            subject.fragment = nil if subject.fragment&.match?(/utm[^a-z]/)

            yield subject, Type, (SIOC + 'BlogPost').R                   # type tag

            blogs = [subject.join('/')]                                  # primary-blog host
            blogs.push @base.join('/') if @host && @host != subject.host # re-blog host
            blogs.map{|blog|
              forum = if subject.host&.match /reddit.com$/
                        ('https://www.reddit.com/' + subject.R.parts[0..1].join('/')).R
                      else
                        blog
                      end
              yield subject, WebResource::To, forum}

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
                yield subject, p, o unless subject == o # emit link unless links to self
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
                crs.map{|cr|yield subject, Creator, cr}
              else # element -> RDF
                yield subject, p, e[3].yield_self{|o|
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
      doc.css('.post, .postCell, .post-container').map{|post|
        num = post.css('a.linkSelf, a.post_no, .postNum a')[0]
        subject = join(num ? num['href'] : ('#' + (post['data-post-no'] || post['id'] || (Digest::SHA2.hexdigest post.to_s))))
        graph = ['https://', subject.host, subject.path.sub(/\.html$/, ''), '/', subject.fragment].join.R

        yield subject, Type, Post.R, graph

        post.css('time, .dateTime').map{|date|
          yield subject, Date, (date['datetime'] || Time.at((date['data-utc'] || date['unixtime']).to_i).iso8601), graph }

        post.css('.labelCreated').map{|created|
          yield subject, Date, Chronic.parse(created.inner_text).iso8601, graph }

        post.css('.name, .post_author, .poster-name, .postername').map{|name|
          yield subject, Creator, name.inner_text, graph }

        post.css('.post-subject, .post_title, .subject, .title').map{|subj|
          yield subject, Title, subj.inner_text, graph }

        post.css('.file-image, .fileThumb, .imgLink').map{|a|
          yield subject, Image, (join a['href']), graph if a['href'] }

        post.css('.post_image, .post-image, img.thumb').map{|img|
          yield subject, Image, (join img.parent['href']), graph }

        post.css('img.multithumb, img.multithumbfirst').map{|img|
          yield subject, Image, (join img.parent.parent['href']), graph }

        post.css('[href$="m4v"], [href$="mp4"], [href$="webm"]').map{|a|
          yield subject, Video, (join a['href']), graph }

        post.css('.body, .divMessage, .message, .post-body, .postMessage, .text').map{|msg|
          msg.css('a[class^="ref"], a[onclick*="Reply"], .post-link, .quotelink, .quoteLink').map{|reply_of|
            yield subject, To, (join reply_of['href']), graph
            reply_of.remove}
          yield subject, Content, msg, graph }

        post.remove }

      doc.css('#boardNavMobile, #delform, #absbot, #navtopright, #postForm, #postingForm, #actionsForm, #thread-interactions').map &:remove
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

          post.css('img').map{|img|
            yield subject, Image, img['src'].R, graph }

          post.css('.e-content').map{|msg|
            yield subject, Content, Webize::HTML.format(msg, self), graph }

          post.remove

        end}
    end

    Markup[Title] = -> title, env {
      if title.class == String
        [{_: :span, class: :title, c: CGI.escapeHTML(title)}, ' ']
      end}

    Markup[Creator] = Markup[To] = Markup['http://xmlns.com/foaf/0.1/maker'] = -> creator, env {
      if creator.class == String || !creator.respond_to?(:R)
        CGI.escapeHTML creator.to_s
      else
        uri = creator.R env
        name = uri.display_name
        color = env[:colors][name] ||= '#%06x' % (rand 16777216)
        {_: :a, href: uri.href, id: 'a' + Digest::SHA2.hexdigest(rand.to_s), class: :fromto, style: "background-color: #{color}; color: black", c: name}
      end}

    MarkupGroup[Post] = -> posts, env {
      if env[:view] == 'table'
        HTML.tabular posts, env
      else
        posts.group_by{|p|(p[To] || [''.R])[0]}.map{|to, posts|
          grouped = posts.size != 1
          color = env[:colors][to.R.display_name] ||= (grouped ? ('#%06x' % (rand 16777216)) : '#444')
          {style: "background: repeating-linear-gradient(-45deg, #000, #000 .875em, #{color} .875em, #{color} 1em); #{grouped ? 'padding: .42em' : ''}",
           c: posts.sort_by!{|r|(r[Content] || r[Image] || [0])[0].size}.map{|post| Markup[Post][post,env]}}}
      end}

    Markup[Post] = -> post, env {
      post.delete Type
      uri = post.delete('uri') || ('#' + Digest::SHA2.hexdigest(rand.to_s))
      resource = uri.R env
      authors = post.delete(Creator) || []
      date = (post.delete(Date) || [])[0]
      uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
      hasPointer = false
      local_id = if !resource.path || (resource.host == env[:base].host && resource.path == env[:base].path)
                   resource.fragment
                 else
                   uri_hash
                 end
      if authors.find{|a| KillFile.member? a.to_s}
        authors.map{|a| CGI.escapeHTML a.R.display_name if a.respond_to? :R}
      else
        {class: resource.deny? ? 'blocked post' : :post, id: local_id,
         c: ["\n",
             (post.delete(Title)||[]).map(&:to_s).map(&:strip).compact.-([""]).uniq.map{|title|
               title = title.to_s.sub(/\/u\/\S+ on /,'')
               unless env[:title] == title
                 env[:title] = title
                 hasPointer = true
                 [{_: :a,  id: 'r'+Digest::SHA2.hexdigest(rand.to_s), class: :title,
                   href: resource.href, c: [(post.delete(Schema+'icon')||[]).map{|i|{_: :img, src: i.href}},CGI.escapeHTML(title)]}, " \n"]
               end},
             {class: :pointer,
              c: [({_: :a, class: :date, href: 'http://localhost:8000/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date), ' ',
                  ({_: :a, c: '☚', href: resource.href, id: 'r' + Digest::SHA2.hexdigest(rand.to_s)} unless hasPointer)]},
             {_: :table, class: :fromto,
              c: {_: :tr,
                  c: [{_: :td,
                       c: authors.map{|f|Markup[Creator][f,env]},
                       class: :from}, "\n",
                      {_: :td, c: '&rarr;'},
                      {_: :td,
                       c: [(post.delete(To)||[]).map{|f|Markup[To][f,env]},
                           post.delete(SIOC+'reply_of')],
                       class: :to}, "\n"]}},
             {class: :body,
              c: [({class: :abstract, c: post.delete(Abstract)} if post.has_key? Abstract),
                  {class: :content,
                   c: [(post.delete(Image) || []).map{|i| Markup[Image][i,env]},
                       ((env.has_key? :proxy_href) && (post.has_key? Content)) ? Webize::HTML.proxy_hrefs(post.delete(Content), env) : post.delete(Content),
                       post.delete(SIOC + 'richContent')]},
                  MarkupGroup[Link][post.delete(Link) || [], env],
                  (["<br>\n", HTML.keyval(post,env)] unless post.keys.size < 1)]}]}
      end}

  end
end
