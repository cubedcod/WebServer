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

  module CSS
    class Format < RDF::Format
      content_type 'text/css', :extension => :css
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#css').R
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
        css_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def css_triples
      end
    end
  end

  module MSWord
    class Format < RDF::Format
      content_type 'application/msword', extension: :docx
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
        html = RDF::Literal `docx2txt #{@base.shellPath}`
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
                   text/javascript;q=0.8),
                   extensions: [:bash, :c, :cpp, :gemspec, :h, :hs, :js, :pl, :py, :rb, :sh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @lang = options[:lang]
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
        yield Title.R, @base.basename
        lang = "-l #{@lang}" if @lang
        html = RDF::Literal [`pygmentize #{lang} -f html #{@base.shellPath}`,'<style>',CodeCSS,'</style>'].join
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
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r rss rssfeed
 sports source status story
 t the threads topic
 uk utm www}

    class Format < RDF::Format
      content_type 'text/plain', :extension => :txt
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
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
        text_triples{|s,p,o|
          fn.call RDF::Statement.new(s, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @base)}
      end

      def text_triples
        yield @body, Content, WebResource::HTML.render({_: :pre, style: 'white-space: pre-wrap',
                                              c: @doc.hrefs{|p,o| # hypertextize
                                                # yield detected links to consumer
                                                yield @body, p, o
                                                yield o, Type, (W3 + '2000/01/rdf-schema#Resource').R}})
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

  module TempFile
    class Format < RDF::Format
      content_type 'text/tmpfile', :extension => :tmp
      content_encoding 'utf-8'
      reader { Plaintext::Reader }
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
        fn.call RDF::Statement.new(@base, Type.R, (Schema+'BreadcrumbList').R)
        @doc.lines.map(&:chomp).map{|line|
          fn.call RDF::Statement.new @base, ('https://schema.org/itemListElement').R, line.R unless line.empty?
        }
      end
    end
  end
end
