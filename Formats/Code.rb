require 'json'
module Webize
  module Sourcecode
    class Format < RDF::Format
      content_type 'application/*'
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        #@doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri].R
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
        lang = "-l #{@lang}" if @lang
        html = RDF::Literal `pygmentize #{lang} -f html #{@base.shellPath}`
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
