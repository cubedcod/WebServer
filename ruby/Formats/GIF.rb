module Webize
  module GIF
    class Format < RDF::Format
      content_type 'image/gif', :extension => :gif
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil #puts("EXIF read failed on #{@subject}")
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
      end
    end
  end
end
