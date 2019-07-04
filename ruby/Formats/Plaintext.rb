module Webize
  module Plaintext
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
        text_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def text_triples
        yield @subject, Content, HTML.render({_: :pre, style: 'white-space: pre-wrap',
                                              c: @doc.hrefs{|p,o| # hypertextize
                                                # yield detected links to consumer
                                                yield @subject, p, o
                                                yield o, Type, (W3 + '2000/01/rdf-schema#Resource').R}})
      end
    end
  end
end
