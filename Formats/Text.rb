# coding: utf-8

class String

  # text -> HTML, yielding found (rel, href) tuples to block
  def hrefs &blk
    # URIs are sometimes wrapped in (). an opening/closing pair is required for capture of (), '"<>[] never captured. , and . can appear in URL but not at the end
    pre, link, post = self.partition(/((gemini|https?):\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub("\n",'<br>') + # pre-match
      (link.empty? && '' ||
       '<a href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = link.R
        img = nil
        if blk
          type = case link
                 when /[\.=](gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)([\?&]|$)/i
                   img = '<img src="' + resource.uri + '">'
                   WebResource::Image
                 when /(youtu.?be|(mkv|mp4|webm)(\?|$))/i
                   WebResource::Video
                 else
                   WebResource::Link
                 end
          yield type, resource
        end
        [img,
         CGI.escapeHTML(resource.uri.sub(/^http:../,'')[0..79])].join) +
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
        @path = options[:path] || @base.fsPath
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
        html = RDF::Literal '<pre>' + `#{converter} #{Shellwords.escape @path}` + '</pre>'
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
 html http https id in index irc is item local medium
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

    class Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
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
        text_triples{|s, p, o, graph=nil|
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     graph_name: graph || @base)}
      end

      def text_triples &f
        basename = File.basename (@base.path || '/'), '.txt'
        if basename == 'twtxt'
          twtxt_triples &f
        elsif @base.ext == 'irc'
          chat_triples &f
        else
          yield @base, Content, Webize::HTML.format(WebResource::HTML.render({_: :pre,
                                                                              c: @doc.lines.map{|line|
                                                                                line.hrefs{|p,o|
                                                                                  yield @base, p, o  unless o.deny?
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
