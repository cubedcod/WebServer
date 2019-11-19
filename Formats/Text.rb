# coding: utf-8

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
        CGI.escapeHTML(resource.uri.sub(/^http:../,'')[0..79])) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # prob not properly tail-recursive, getting overflow on logfiles, may need to rework
  rescue
    puts "failed to scan #{self}"
    ''
  end
end

module Webize
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
 sports source story
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
        webvtt = @base.host ? WebVTT.from_blob(@doc) : WebVTT.read(@base.relPath)
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
end
