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
        @base = options[:base_uri].R
#        require 'pdf/reader'
#        @doc = begin
#                 ::PDF::Reader.new input
#               rescue Exception => e
#                 puts e.class, e.message
#               end
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
        pdf_tuples{|p,o|
          fn.call RDF::Statement.new(@base, p, o, :graph_name => @base)}
      end

      def pdf_tuples
=begin
        ## use PDF library
        return unless @doc && @doc.respond_to?(:info)
        (@doc.info || []).map{|k,v|
          k = {
            Author: Creator,
            Title: Title,
            ModDate: Date,
          }[k] || ('#' + k.to_s.gsub(' ','_'))
          yield k, v
        }
        @doc.pages.each do |page|
          yield Content, page.text.hrefs
        end
=end
        ## use poppler-utils
        location = @base.shellPath
        location += '.pdf' unless @base.ext == 'pdf'
        html = RDF::Literal `pdftohtml -s -stdout #{location}`
        #html = RDF::Literal '<pre>' + `pdftotext #{location} -` + '</pre>'
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
