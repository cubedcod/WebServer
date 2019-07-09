module Webize
  module PDF
    class Format < RDF::Format
      content_type 'application/pdf', :extension => :pdf
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        require 'pdf/reader'
        @subject = (options[:base_uri] || '#image').R
        @doc = ::PDF::Reader.new input
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
        pdf_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def pdf_tuples
        @doc.info.map{|k,v|
          k = {
            Author: Creator,
            Title: Title,
            ModDate: Date,
          }[k] || ('#' + k.to_s.gsub(' ','_'))
          yield k, v
        }
        puts @doc.metadata
        @doc.pages.each do |page|
          yield Content, page.text.hrefs
        end
      end

    end
  end
end
