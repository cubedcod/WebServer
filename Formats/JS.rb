require 'json'
module Webize
  module JS
    class Format < RDF::Format
      content_type 'application/javascript',
                   extension: :js,
                   aliases: %w(
                   application/x-javascript;q=0.8
                   text/javascript;q=0.8)
      content_encoding 'utf-8'

      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @subject = (options[:base_uri] || '#js').R
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
        js_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def js_triples
      end
    end
  end

  module JSON
    class Format < RDF::Format
      content_type 'application/json', :extension => :json
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @subject = (options[:base_uri] || '#image').R 
        @json = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue {}
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
        scanContent{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal (if [Abstract,Content].member? p
                                                                                    HTML.clean o
                                                                                   else
                                                                                     o
                                                                                    end)
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end
      def scanContent &f
        # triplr host-binding
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, @json, &f
        end
      end
    end
  end
end
