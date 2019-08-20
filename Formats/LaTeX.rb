module Webize
  module LaTeX
    class Format < RDF::Format
      content_type 'text/latex', :extension => :tex
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = options[:base_uri].R
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
        tex_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p.R, o, :graph_name => @subject)}
      end

      def tex_tuples
        puts @subject
      end
    end
  end
end
