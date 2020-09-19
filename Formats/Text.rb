# coding: utf-8
require 'redcarpet'

module Redcarpet
  module Render
    class Pygment < HTML
      def block_code(code, lang)
        if lang
          IO.popen("pygmentize -l #{Shellwords.escape lang.downcase} -f html",'r+'){|p|
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

  # text -> HTML, while yielding found (rel, href) tuples to block
  def hrefs &blk # wrapping <>()[] and trailing ,. chars not captured in URL
    pre, link, post = self.partition(/(https?:\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub("\n",'<br>') + # pre-match
      (link.empty? && '' ||
       '<a href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
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

  module Sourcecode
    class Format < RDF::Format
      content_type 'application/javascript',
                   aliases: %w(
                   application/x-javascript;q=0.8
                   text/javascript;q=0.8
                   text/x-perl;q=0.8
                   text/x-ruby;q=0.8
                   text/x-shellscript;q=0.8
                   ),
                   extensions: [:bash, :c, :cpp, :erb, :gemspec, :go, :h, :hs, :js, :pl, :proto, :py, :rb, :sh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @lang = 'html' if @base.ext == 'erb'
        @lang = 'ruby' if options[:content_type] == 'text/x-ruby'
        @lang = 'shell' if options[:content_type] == 'text/x-shellscript'
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
        yield Type.R, (Schema + 'Code').R
        lang = "-l #{@lang}" if @lang
        html = RDF::Literal [`pygmentize #{lang} -f html #{@base.shellPath}`,'<style>',CodeCSS,'</style>'].join.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end

  module Markdown
    class Format < RDF::Format
      content_type 'text/markdown', :extensions => [:markdown, :md]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri].R
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
        yield @subject, Content, (Webize::HTML.format ::Redcarpet::Markdown.new(::Redcarpet::Render::Pygment, fenced_code_blocks: true).render(@doc), @base)
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
        yield Content, WebResource::HTML.render({_: :pre, style: 'white-space: pre-wrap', c: @doc})
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
        elsif @base.ext == 'irc' # irssi: /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
          base = @base.to_s
          net, channame = @base.basename.split '.'
          channame = Rack::Utils.unescape_path(channame)[1..-1]
          chan = (base + '#' + channame).R
          day = @base.parts[0..2].join('-') + 'T'
          lines = 0
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
            else
              if re = tokens.join(' ').match(/<[\s@+*]*([^>]+)>\s*(.*)?/)
                nick = re[1]
                msg = re[2]
              end
            end
            timestamp = day + time
            subject = base + '#' + channame + (lines += 1).to_s
            yield subject, Type, (SIOC + 'InstantMessage').R
            yield subject, Date, timestamp
            yield subject, To, chan
            yield subject, Creator, (dirname + '?q=' + nick + '&sort=date&view=table#' + nick).R
            yield subject, Content, Webize::HTML.format(msg.hrefs{|p,o| yield subject, p, o}, @base) if msg
          }
        else # basic text content
          yield @body, Content, Webize::HTML.format(WebResource::HTML.render({_: :pre, style: 'white-space: pre-wrap',
                                                                              c: @doc.lines.map{|line|
                                                                                line.hrefs{|p,o| # hypertextize
                                                                                  # yield detected links to consumer
                                                                                  yield @body, p, o
                                                                                  yield o, Type, (W3 + '2000/01/rdf-schema#Resource').R}}}), @base)
        end
      end
    end
  end

  module VTT
    class Format < RDF::Format
      content_type 'text/vtt', :extension => :vtt
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      ENV['BUNDLE_GEMFILE'] = File.expand_path '../Gemfile', File.dirname(__FILE__)
      def initialize(input = $stdin, options = {}, &block)
        require 'bundler'
        Bundler.setup
        require "webvtt"

        @doc = input.respond_to?(:read) ? input.read : input
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
        vtt_triples{|s,p,o|
          fn.call RDF::Statement.new(s, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @base)}
      end

      def vtt_triples
        webvtt = @base.host ? WebVTT.from_blob(@doc) : WebVTT.read(@base.fsPath)
        line = 0
        webvtt.cues.each do |cue|
          subject = @base.join '#l' + line.to_s; line += 1
          yield subject, Type, Post.R
          yield subject, Date, cue.start
          yield subject, Content, cue.text
        end
      end
    end
  end

  module URIlist
    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'
      reader { Reader }
    end
    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R.path.sub(/.u$/,'').R
        @doc = input.respond_to?(:read) ? input.read : input
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
        @doc.lines.map(&:chomp).map{|line|
          fn.call RDF::Statement.new line.R, Type.R, (W3 + '2000/01/rdf-schema#Resource').R unless line.empty? || line.match?(/^#/)}
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
      abbreviated = !qs.has_key?('fullContent')

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
        r.delete Content if abbreviated
      }

      # CSS
      graph['#abstracts'] = {Abstract => [HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})]}
    end

  end

end
