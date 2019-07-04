module Webize
  module Calendar
    class Format < RDF::Format
      content_type 'text/calendar', :extension => :ics
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
        calendar_triples{|s,p,o|
          fn.call RDF::Statement.new(@subject, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => @subject)}
      end

      def calendar_triples
        Icalendar::Calendar.parse(@doc).map{|cal|
          cal.events.map{|event|
            subject = event.url || ('#event'+rand.to_s.sha2)
            yield subject, Date, event.dtstart
            yield subject, Title, event.summary
            yield subject, Abstract, CGI.escapeHTML(event.description)
            yield subject, '#geo', event.geo if event.geo
            yield subject, '#location', event.location if event.location
          }}
      end
    end
  end
end
