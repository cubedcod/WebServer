%w(chronic date icalendar).map{|_| require _}

class WebResource

  module URIs

    DayDir  = /^\/\d\d\d\d\/\d\d\/\d\d/
    HourDir = /^\/\d\d\d\d\/\d\d\/\d\d\/\d\d/

  end

  module HTML
    Markup['http://purl.org/dc/terms/created'] = Markup['http://purl.org/dc/terms/modified'] = Markup[Date] = -> date, env {
      {_: :a, class: :date, c: date, href: 'http://localhost:8000/' + date[0..13].gsub(/[-T:]/,'/')}}
  end

  module HTTP

    def dateDir
      time = Time.now.utc
      loc = time.strftime(case parts[0][0].downcase
                          when 'y'
                            '/%Y/'
                          when 'm'
                            '/%Y/%m/'
                          when 'd'
                            '/%Y/%m/%d/'
                          when 'h'
                            '/%Y/%m/%d/%H/'
                          else
                          end)
      [303, env[:resp].update({'Location' => loc + parts[1..-1].join('/') + (query ? ('?'+query) : '')}), []]
    end

    def timeMeta
      n = nil # next-page locator
      p = nil # prev-page locator

      # read date components from path
      dp = []; ps = parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)

      case dp.length
      when 1 # Y
        year = dp[0]
        n = '/' + (year + 1).to_s
        p = '/' + (year - 1).to_s
      when 2 # Y-m
        year = dp[0]
        m = dp[1]
        n = m >= 12 ? "/#{year + 1}/#{01}" : "/#{year}/#{'%02d' % (m + 1)}"
        p = m <=  1 ? "/#{year - 1}/#{12}" : "/#{year}/#{'%02d' % (m - 1)}"
      when 3 # Y-m-d
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          p = (day-1).strftime('/%Y/%m/%d')
          n = (day+1).strftime('/%Y/%m/%d')
        end
      when 4 # Y-m-d-H
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          hour = dp[3]
          p = hour <=  0 ? (day - 1).strftime('/%Y/%m/%d/23') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour-1)))
          n = hour >= 23 ? (day + 1).strftime('/%Y/%m/%d/00') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour+1)))
        end
      end

      # append non-date components of path, and trailing slash
      remainder = ps.empty? ? '' : ['', *ps].join('/')
      remainder += '/' if env['REQUEST_PATH'] && env['REQUEST_PATH'][-1] == '/'
      q = (env['QUERY_STRING'] && !env['QUERY_STRING'].empty?) ? ('?' + env['QUERY_STRING']) : ''

      # set metadata
      env[:links][:prev] = p + remainder + q + '#prev' if p
      env[:links][:next] = n + remainder + q + '#next' if n
    end

  end
end

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
            subject = event.url || ('#event' + Digest::SHA2.hexdigest(rand.to_s))
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
