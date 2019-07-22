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
        mail_triples{|s,p,o,graph=nil|
          fn.call RDF::Statement.new(s.R, p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if p == Content
                                                                                            l),
                                     :graph_name => s.R)}
      end
      def mail_triples &b
        m = ::Mail.new @doc
        unless m
          puts "mail parse failed:", @doc
          return
        end
        # Message-ID
        id = m.message_id || m.resent_message_id || Digest::SHA2.hexdigest(rand.to_s)

        # Message URI
        msgURI = -> id {
          h = Digest::SHA2.hexdigest id
          ['', 'msg', h[0], h[1], h[2], id.gsub(/[^a-zA-Z0-9]+/,'.')[0..96], '#this'].join('/').R}
        resource = msgURI[id]
        e = resource.uri

        srcDir = resource.path.R          # message dir
        srcFile = (srcDir + 'this.eml').R # message file
        unless srcFile.exist?
          srcFile.writeFile @doc # store in canonical-location
        end
        yield e, DC + 'identifier', id # Message-ID
        yield e, Type, (SIOC + 'MailMessage').R

        # HTML
        htmlFiles, parts = m.all_parts.push(m).partition{|p|p.mime_type=='text/html'}
        htmlCount = 0
        htmlFiles.map{|p| # HTML file
          html = (srcDir + "#{htmlCount}.html").R # file ref
          yield e, DC+'hasFormat', html           # file ref in RDF
          unless html.exist?
            html.writeFile p.decoded  # store HTML email
          end
          htmlCount += 1 } # increment count

        # plaintext
        parts.select{|p|
          (!p.mime_type || p.mime_type == 'text/plain') && # text parts
            ::Mail::Encodings.defined?(p.body.encoding)      # decodable?
        }.map{|p|
          yield e, Content,
                WebResource::HTML.render(p.decoded.lines.to_a.map{|l| # split lines
                              l = l.chomp # strip any remaining [\n\r]
                              if qp = l.match(/^((\s*[>|]\s*)+)(.*)/) # quoted line
                                depth = (qp[1].scan /[>|]/).size # > count
                                if qp[3].empty? # drop blank quotes
                                  nil
                                else # wrap quotes in <span>
                                  indent = "<span name='quote#{depth}'>&gt;</span>"
                                  {_: :span, class: :quote,
                                   c: [indent * depth,' ',
                                       {_: :span, class: :quoted,
                                        c: qp[3].hrefs{|p,o|
                                          yield e, p, o }}]}
                                end
                              else # unquoted line
                                [l.hrefs{|p, o| yield e, p, o}]
                              end}.map{|line| [line, '<br>']})}

        # recursive contained messages: digests, forwards, archives
        parts.select{|p|p.mime_type=='message/rfc822'}.map{|m|
          content = m.body.decoded                       # decode message
          f = (srcDir + Digest::SHA2.hexdigest(content) + '.inlined.eml').R # storage location
          f.writeFile content if !f.exist?               # store message
          f.triplrMail &b} # triplr on contained message

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
            yield e, Creator, name
          } if fr.respond_to? :addrs}

        m['X-Mailer'] && m['X-Mailer'].yield_self{|m|
          yield e, SIOC+'user_agent', m.to_s}

        # To
        to = []
        %w{to cc bcc resent_to}.map{|p|      # recipient fields
          m.send(p).yield_self{|r|           # recipient lookup
            ((r.class == Array || r.class == ::Mail::AddressContainer) ? r : [r]).compact.map{|r| # recipient
            to.push r.downcase }}} # queue for indexing
        m['X-BeenThere'].yield_self{|b|(b.class == Array ? b : [b]).compact.map{|r|to.push r.to_s}} # anti-loop recipient
        m['List-Id'] && m['List-Id'].yield_self{|name|yield e, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,'')} # mailinglist name

        # Subject
        subject = nil
        m.subject && m.subject.yield_self{|s|
          subject = s
          subject.scan(/\[[^\]]+\]/){|l| yield e, Schema + 'group', l[1..-2]}
          yield e, Title, subject}

        # Date
        date = m.date || Time.now rescue Time.now
        date = Time.parse(date.to_s) unless [Time, DateTime].member? date.class
        dstr = date.utc.iso8601
        yield e, Date, dstr
        dpath = '/' + dstr[0..6].gsub('-','/') + '/msg/' # month

        # index addresses
        [*from,*to].map{|addr|
          user, domain = addr.split '@'
          if user && domain
            apath = dpath + domain + '/' + user # address
            yield e, (from.member? addr) ? Creator : To, apath.R # To/From triple
            if subject
              slug = subject.scan(/[\w]+/).map(&:downcase).uniq.join('.')[0..63]
              mpath = apath + '.' + dstr[8..-1].gsub(/[^0-9]+/,'.') + slug # (month,addr,title) path
              [(mpath + (mpath[-1] == '.' ? '' : '.')  + 'eml').R, # monthdir entry
               ('mail/cur/' + Digest::SHA2.hexdigest(id) + '.eml').R].map{|entry|     # maildir entry
                srcFile.link entry unless entry.exist?} # link if missing
            end
          end
        }

        # index bidirectional refs
        %w{in_reply_to references}.map{|ref|
          m.send(ref).yield_self{|rs|
            (rs.class == Array ? rs : [rs]).compact.map{|r|
              dest = msgURI[r]
              yield e, SIOC+'reply_of', dest
              destDir = dest.path.R
              destDir.mkdir
              destFile = (destDir + 'this.eml').R
              # bidirectional reference link
              rev = (destDir + Digest::SHA2.hexdigest(id) + '.eml').R
              rel = (srcDir + Digest::SHA2.hexdigest(r) + '.eml').R
              if !rel.exist? # link missing
                if destFile.exist? # target exists
                  destFile.link rel
                else # link anyway, referenced node may appear
                  destFile.ln_s rel unless rel.node.symlink?
                end
              end
              srcFile.link rev if !rev.exist?}}}

        # attachments
        m.attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p| # decodability check
          name = p.filename && !p.filename.empty? && p.filename || # explicit name
                 (Digest::SHA2.hexdigest(rand.to_s) + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generated name
          file = (srcDir + name).R                 # file location
          unless file.exist?
            file.writeFile p.body.decoded # store attachment
          end
          yield e, SIOC+'attachment', file         # file pointer
          if p.main_type=='image'                  # image attachments
            yield e, Image, file                   # image link in RDF
            yield e, Content,                      # image link in HTML
                  WebResource::HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}) # render HTML
          end }
      end

    end
  end
end
