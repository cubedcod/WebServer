# coding: utf-8

class String

  # text -> HTML, yielding found (rel, href) tuples to block
  def hrefs &blk
    pre, link, post = self.partition(/(https?:\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/) # wrapping <>()[] and trailing ,. not captured
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub("\n",'<br>') + # pre-match
      (link.empty? && '' ||
       '<a href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = link.R
        if blk
          type = case link
                 when /(gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)(\?|$)/i
                   WebResource::Image
                 when /(youtu.?be|(mkv|mp4|webm)(\?|$))/i
                   WebResource::Video
                 else
                   WebResource::Link
                 end
          yield type, resource
        end
        CGI.escapeHTML(resource.uri.sub(/^http:../,'')[0..79])) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # prob not tail-recursive, getting overflow on logfiles, may need to rework
  rescue
    puts "failed to scan #{self}"
    ''
  end

end

module Webize

  module MSWord
    class Format < RDF::Format
      content_type 'application/msword', extensions: [:doc, :docx]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
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
        source_tuples{|p,o|
          fn.call RDF::Statement.new(@base, p, o, :graph_name => @base)}
      end

      def source_tuples
        yield Type.R, (Schema + 'Document').R
        yield Title.R, @base.basename
        converter = @base.ext == 'doc' ? :antiword : :docx2txt
        html = RDF::Literal '<pre>' + `#{converter} #{@base.shellPath}` + '</pre>'
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end

  module NFO
    class Format < RDF::Format
      content_type 'text/nfo', :extension => :nfo
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).force_encoding('CP437').encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri].R
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
        nfo_triples{|p,o|
          fn.call RDF::Statement.new(@base, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @base)}
      end

      def nfo_triples
        yield Content, WebResource::HTML.render({_: :pre, c: @doc})
      end
    end
  end

  module Plaintext

    BasicSlugs = %w{
 amp article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feedburner feeds feedproxy forum forums
 go google gov
 html in index irc is local medium
 net news org p php post
 r reddit rs rss rssfeed
 s sports source status story
 t the thread threads to top topic twitter type
 uk utm www}

    class Format < RDF::Format
      content_type 'text/plain', :extensions => [:conf, :irc, :log, :txt]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        @base = options[:base_uri].R
        @body = @base.join '#this'
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
        text_triples{|s, p, o, graph=nil|
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     graph_name: graph || @base)}
      end

      def text_triples
        basename = File.basename @base.path, '.txt'
        dirname = File.dirname @base.path
        if basename == 'twtxt' # https://twtxt.readthedocs.io/
          @doc.lines.grep(/^[^#]/).map{|line|
            date, msg = line.split /\t/
            graph = @base.join (dirname == '/' ? '' : dirname) + '/twtxt.' + date.gsub(/\D/,'.')
            subject = graph.join '#msg'
            yield subject, Type, Post.R, graph
            yield subject, Date, date, graph
            yield subject, Content, Webize::HTML.format(msg.hrefs, @base), graph if msg
            yield subject, Creator, (@base.host + dirname).split(/\W/).join('.'), graph
            yield subject, To, @base, graph
          }
        elsif @base.ext == 'irc'
          # irssi:
          #  /set autolog on
          #  /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
          # weechat:
          #  /set logger.mask.irc "%Y/%m/%d/%H/$server.$channel.irc"
          network, channame = @base.basename.split '.'
          channame = Rack::Utils.unescape_path(channame).gsub('#','')
          chan = ('#' + channame).R
          day = @base.parts[0..2].join('-') + 'T'
          hourslug = @base.parts[0..3].join
          lines = 0
          ts = {}
          @doc.lines.grep(/^[^-]/).map{|msg|
            tokens = msg.split /\s+/
            time = tokens.shift
            if ['*','-!-'].member? tokens[0] # actions, joins, parts
              nick = tokens[1]
              msg = tokens[2..-1].join ' '
              msg = '/me ' + msg if tokens[0] == '*'
            elsif tokens[0].match? /^-.*:.*-$/ # notices
              nick = tokens[0][1..tokens[0].index(':')-1]
              msg = tokens[1..-1].join ' '
            elsif re = msg.match(/<[\s@+*]*([^>]+)>\s?(.*)?/)
              nick = re[1]
              msg = re[2]
            end
            nick = CGI.escape(nick || 'anonymous')
            timestamp = day + time
            subject = '#' + channame + hourslug + (lines += 1).to_s
            yield subject, Type, (SIOC + 'InstantMessage').R
            ts[timestamp] ||= 0
            yield subject, Date, [timestamp, '%02d' % ts[timestamp]].join('.')
            ts[timestamp] += 1
            yield subject, To, chan
            yield subject, Creator, (dirname + '/*irc?q=' + nick + '&sort=date&view=table#' + nick).R
            yield subject, Content, ['<pre>',
                                     msg.hrefs{|p,o|
                                       yield subject, p, o},
                                     '</pre>'].join if msg
          }
        else # basic text content
          yield @body, Content, Webize::HTML.format(WebResource::HTML.render({_: :pre,
                                                                              c: @doc.lines.map{|line|
                                                                                line.hrefs{|p,o| # emit references as RDF
                                                                                  yield @body, p, o  unless o.deny?
                                                                                  # yield o, Type, (W3+'2000/01/rdf-schema#Resource').R
                                                                                }}}), @base)
        end
      end
    end
  end

end

class WebResource

  module HTML

    def htmlGrep
      graph = env[:graph]
      qs = query_values || {}
      q = qs['Q'] || qs['q']
      return unless graph && q

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
      }

      # CSS
      graph['#abstracts'] = {Abstract => [HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})]}
    end

  end

end
