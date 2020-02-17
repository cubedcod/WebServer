# coding: utf-8
require 'mail'
module Webize
  module Mail
    class Format < RDF::Format
      content_type 'message/rfc822', :extension => :eml
      content_encoding 'utf-8'
      reader { Reader }
      def self.symbols
        [:mail]
      end
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri]
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
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
        mail_triples(@doc){|subject, predicate, o, graph|
          fn.call RDF::Statement.new(subject.R, predicate.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if predicate == Content
                                                                                            l),
                                     :graph_name => graph)}
      end

      def mail_triples body, &b
        m = ::Mail.new body; return puts "mail-parse failed #{@base}" unless m

        # Message resource
        id = m.message_id || m.resent_message_id || Digest::SHA2.hexdigest(rand.to_s)
        graph = ('/msg/' + Rack::Utils.escape_path(id)).R
        mail = (graph + '#msg').R

        yield mail, Type, (SIOC + 'MailMessage').R, graph

        # HTML message
        htmlFiles, parts = m.all_parts.push(m).partition{|p| p.mime_type == 'text/html' }
        htmlCount = 0
        htmlFiles.map{|p|
          html = ('/' + graph.fsPath + ".#{htmlCount}.html").R # HTML-file
          yield mail, DC + 'hasFormat', html, graph   # reference
          html.writeFile p.decoded unless html.node.exist? # store
          htmlCount += 1 }

        # plaintext message
        parts.select{|p|
          (!p.mime_type || p.mime_type.match?(/^text\/plain/)) && # text parts
            ::Mail::Encodings.defined?(p.body.encoding)    # decodable?
        }.map{|p|
          yield mail, Content,
                WebResource::HTML.render(p.decoded.lines.to_a.map{|l| # split lines
                              l = l.chomp # strip any remaining [\n\r]
                              if qp = l.match(/^(\s*[>|][>|\s]*)(.*)/) # quoted line
                                if qp[2].empty? # drop blank quotes
                                  nil
                                else # quote
                                  {_: :span, class: :quote,
                                   c: [qp[1].gsub('>','&gt;'), qp[2].hrefs{|p,o|
                                         yield mail, p, o, graph }]}
                                end
                              else # fresh line
                                [l.hrefs{|p, o|
                                   yield mail, p, o, graph}]
                              end}.map{|line| [line, "<br>\n"]}), graph}

        # recursively contained messages: digests, forwards, archives
        parts.select{|p|p.mime_type=='message/rfc822'}.map{|m|
          mail_triples m.body.decoded, &b}

        # From
        from = []
        m.from.yield_self{|f|
          ((f.class == Array || f.class == ::Mail::AddressContainer) ? f : [f]).compact.map{|f|
            noms = f.split ' '
            if noms.size > 2 && noms[1] == 'at'
              f = "#{noms[0]}@#{noms[2]}"
            end
            from.push f.downcase}} # queue address for indexing + triple-emitting
        m[:from] && m[:from].yield_self{|fr|
          fr.addrs.map{|a|
            name = a.display_name || a.name # human-readable name
            yield mail, Creator, name, graph
          } if fr.respond_to? :addrs}

        # To
        to = []
        %w{to cc bcc resent_to}.map{|p|      # recipient fields
          m.send(p).yield_self{|r|           # recipient lookup
            ((r.class == Array || r.class == ::Mail::AddressContainer) ? r : [r]).compact.map{|r| # recipient
            to.push r.downcase }}} # queue for indexing
        m['X-BeenThere'].yield_self{|b|(b.class == Array ? b : [b]).compact.map{|r|to.push r.to_s}} # anti-loop recipient
        m['List-Id'] && m['List-Id'].yield_self{|name|
          yield mail, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,''), graph} # mailinglist name

        # Subject
        subject = nil
        m.subject && m.subject.yield_self{|s|
          subject = s
          subject.scan(/\[[^\]]+\]/){|l|
            yield mail, Schema + 'group', l[1..-2], graph}
          yield mail, Title, subject, graph}

        # Date
        date = m.date || Time.now rescue Time.now
        timestamp = ([Time, DateTime].member?(date.class) ? date : Time.parse(date.to_s)).iso8601
        yield mail, Date, timestamp, graph

        mailFile = ('mail/cur/' + timestamp.gsub(/\D/,'.') + Digest::SHA2.hexdigest(id) + '.eml').R
        mailFile.writeFile body unless mailFile.node.exist?

        # index addresses
        [*from, *to].map{|addr|
          user, domain = addr.split '@'
          if user && domain
            apath = '/mail/' + domain + '/' + user + '/' # address container
            yield mail, from.member?(addr) ? Creator : To, apath.R, graph # To/From triple
            if subject
              slug = subject.scan(/[\w]+/).map(&:downcase).uniq.join('.')[0..63]
              addrIndex = (apath + timestamp + '.' + slug).R
              yield mail, Title, subject, addrIndex, graph if subject
              yield mail, Date, timestamp, addrIndex, graph
            end
          end }

        # references
        %w{in_reply_to references}.map{|ref|
          m.send(ref).yield_self{|rs|
            (rs.class == Array ? rs : [rs]).compact.map{|r|
              msg = ('/msg/' + Rack::Utils.escape_path(r)).R
              yield mail, SIOC + 'reply_of', msg, graph
              yield msg, SIOC + 'has_reply', mail, graph
            }}}

        # attachments
        m.attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p|     # decodability check
          name = p.filename && !p.filename.empty? && p.filename || # attachment name
                 (Digest::SHA2.hexdigest(rand.to_s) + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generate name
          file = (graph.fsPath + '.' + name).R   # file location
          unless file.node.exist?              # store file
            file.writeFile p.body.decoded.force_encoding 'UTF-8'
          end
          yield mail, SIOC+'attachment', file, graph # attachment pointer
          if p.main_type == 'image'           # image attachments
            yield mail, Image, file, graph    # image link in RDF
            yield mail, Content,              # image link in HTML
                  WebResource::HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}), graph # render HTML
          end }

        yield mail, SIOC+'user_agent', m['X-Mailer'].to_s, graph if m['X-Mailer']
      end
    end
  end
end
