module Webize
  module PNG
    class Format < RDF::Format
      content_type 'image/png', :extension => :png
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        #@img = Exif::Data.new(input.respond_to?(:read) ? input.read : input)
        @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
end
