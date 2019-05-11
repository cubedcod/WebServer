# coding: utf-8
class WebResource
  module URIs

    FeedURL = {}

    ConfDir.join('feeds/*.u').R.glob.map{|list|
      list.lines.map{|u|
        FeedURL[u] = u.R }}

  end
  module HTTP

    def self.getFeeds
      FeedURL.values.map{|feed| feed.remoteNode rescue nil}
      nil
    end

    PathGET['/subscribe'] = -> r {
      url = (r.q['u'] || '/').R
      url.subscribe
      [302, {'Location' => url}, []]}

    PathGET['/unsubscribe']  = -> r {
      url = (r.q['u'] || '/').R
      url.unsubscribe
      [302, {'Location' => url}, []]}

  end
  module Feed

    include URIs

    def feeds
      puts (nokogiri.css '[rel=alternate]').map{|u|join u.attr :href}.uniq
    end

    def subscribable?
      # feed-MIME match
      return true if env[:feed]
      # feed-URL match
      return true if host && FeedURL['//' + host + path]
      # host match
      case host
      when /\.reddit.com$/
        parts[0] == 'r'
      when /twitter.com$/
        true
      else
        false
      end
    end

    def subscribe
      subscriptionFile.e || subscriptionFile.touch
    end

    def subscribed?
      case host
      when /reddit.com$/
        return false if parts.size < 2
      when /^twitter.com$/
        return false if parts.size < 1
      end
      subscriptionFile.exist?
    end

    def subscriptionFile
      (case host
       when /reddit.com$/
         '/www.reddit.com/r/' + parts[1] + '/.subbed'
       when /^twitter.com$/
         '/twitter.com/' + parts[0] + '/.following'
       else
         '/' + [host, *parts, '.subscribed'].join('/')
       end).R
    end

    def unsubscribe
      subscriptionFile.e && subscriptionFile.node.delete
    end

    class Format < RDF::Format
      content_type     'application/atom+xml', :extension => :atom
      content_encoding 'utf-8'
      reader { WebResource::Feed::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input : StringIO.new(input.to_s)).read.to_utf8
        @base = (options[:base_uri] || '/').R
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

      def each_statement &fn # triples flow (left ← right)
        scanContent(:normalizeDates, :normalizePredicates,:rawTriples){|s,p,o|
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
  end

  include Feed

  module MIME

    def feedMIME?; %w{atom rdf rss}.member?(ext) || mime.match?(/\/(atom|rss|xml)/) end

  end

  module Webize

    def storeFeed
      ('file:' + localPath).R.storeRDF(:format => :feed, :base_uri => uri)
    end

    def triplrCalendar
      cal_file = File.open localPath
      cals = Icalendar::Calendar.parse(cal_file)
      cal = cals.first
      puts cal
      event = cal.events.first
      puts event
    end

    def triplrOPML
      # doc
      base = stripDoc
      yield base.uri, Type, (DC+'List').R
      yield base.uri, Title, basename
      # feeds
      Nokogiri::HTML.fragment(readFile).css('outline[type="rss"]').map{|t|
        s = t.attr 'xmlurl'
        yield s, Type, (SIOC+'Feed').R}
    end

  end

end
