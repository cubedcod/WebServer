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
      EmailAddress = ENV['EMAIL']
      MailDir = (Pathname.new ENV['HOME'] + '/.mail').relative_path_from(PWD).to_s

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
        mail_triples(@doc){|subject, predicate, o, graph=nil|
          fn.call RDF::Statement.new(subject.R,
                                     predicate.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                                            l.datatype=RDF.XMLLiteral if predicate == Content
                                                                                            l),
                                     :graph_name => graph || subject.R)}
      end

      def mail_triples body, &b
        m = ::Mail.new body
        return puts "mail-read failed #{@base}" unless m

        # Message resource
        mailResource = -> id {
          h = Digest::SHA2.hexdigest id
          ['', 'mail', '.msg', h[0], h[1], h[2], id[0..96] + '#msg'].join('/').R}
        id = (m.message_id || m.resent_message_id || Digest::SHA2.hexdigest(rand.to_s)).gsub /[^a-zA-Z0-9]+/, '.'
        mail = mailResource[id]
        yield mail, Type, (SIOC + 'MailMessage').R

        # HTML message
        htmlFiles, parts = m.all_parts.push(m).partition{|p|
          p.mime_type == 'text/html'}
        htmlCount = 0
        htmlFiles.map{|p|
          html = (mail.path + ".#{htmlCount}.html").R # HTML-file
          yield mail, DC + 'hasFormat', html          # reference
          html.write p.decoded unless html.exist? # store
          htmlCount += 1 } # increment count

        # plaintext message
        parts.select{|p|
          (!p.mime_type || p.mime_type == 'text/plain') && # text parts
            ::Mail::Encodings.defined?(p.body.encoding)    # decodable?
        }.map{|p|
          yield mail, Content,
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
                                          yield mail, p, o }}]}
                                end
                              else # unquoted line
                                [l.hrefs{|p, o|
                                   yield mail, p, o}]
                              end}.map{|line| [line, '<br>']})}

        # recursive contained messages: digests, forwards, archives
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
            yield mail, Creator, name
          } if fr.respond_to? :addrs}

        # To
        to = []
        %w{to cc bcc resent_to}.map{|p|      # recipient fields
          m.send(p).yield_self{|r|           # recipient lookup
            ((r.class == Array || r.class == ::Mail::AddressContainer) ? r : [r]).compact.map{|r| # recipient
            to.push r.downcase }}} # queue for indexing
        m['X-BeenThere'].yield_self{|b|(b.class == Array ? b : [b]).compact.map{|r|to.push r.to_s}} # anti-loop recipient
        m['List-Id'] && m['List-Id'].yield_self{|name|
          yield mail, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,'')} # mailinglist name

        # Subject
        subject = nil
        m.subject && m.subject.yield_self{|s|
          subject = s
          subject.scan(/\[[^\]]+\]/){|l|
            yield mail, Schema + 'group', l[1..-2]}
          yield mail, Title, subject}

        # Date
        date = m.date || Time.now rescue Time.now
        timestamp = ([Time, DateTime].member?(date.class) ? date : Time.parse(date.to_s)).utc.iso8601
        yield mail, Date, timestamp

        mailFile = (MailDir + '/cur/' + timestamp.gsub(/\D/,'.') + Digest::SHA2.hexdigest(id) + '.eml').R
        mailFile.write body unless mailFile.exist?

        # index addresses
        [*from, *to].map{|addr|
          user, domain = addr.split '@'
          if user && domain
            apath = '/mail/' + domain + '/' + user + '/' # address container
            yield mail, from.member?(addr) ? Creator : To, apath.R # To/From triple
            if subject
              slug = subject.scan(/[\w]+/).map(&:downcase).uniq.join('.')[0..63]
              addrIndex = (apath + timestamp + '.' + slug).R
              yield mail, Title, subject, addrIndex if subject
              yield mail, Date, timestamp, addrIndex
            end
          end }

        # references
        %w{in_reply_to references}.map{|ref|
          m.send(ref).yield_self{|rs|
            (rs.class == Array ? rs : [rs]).compact.map{|r|
              dest = mailResource[r.gsub /[^a-zA-Z0-9]+/, '.']
              yield mail, SIOC + 'reply_of', dest
              yield dest, SIOC + 'has_reply', mail, (dest.path + '.' + Digest::SHA2.hexdigest(id)).R }}}

        # attachments
        m.attachments.select{|p|
          ::Mail::Encodings.defined?(p.body.encoding)}.map{|p|     # decodability check
          name = p.filename && !p.filename.empty? && p.filename || # attachment name
                 (Digest::SHA2.hexdigest(rand.to_s) + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generate name
          file = (mail.path + '.' + name).R   # attachment location
          unless file.exist?
            file.write p.body.decoded         # store attachment
          end
          yield mail, SIOC+'attachment', file # attachment pointer
          if p.main_type == 'image'           # image attachments
            yield mail, Image, file           # image link in RDF
            yield mail, Content,              # image link in HTML
                  WebResource::HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}) # render HTML
          end }

        yield mail, SIOC+'user_agent', m['X-Mailer'].to_s if m['X-Mailer']
      end
    end
  end
end
class WebResource
  module HTML

    Markup[Creator] = Markup[To] = -> c, env {
      if c.class == Hash || c.respond_to?(:uri)
        u = c.R
        basename = u.basename
        host = u.host
        name = u.fragment ||
               (basename && !['','/'].member?(basename) && basename) ||
               (host && host.sub(/\.com$/,'')) ||
               'user'
        avatar = Avatars[u.to_s.downcase]
        [{_: :a, href: u.to_s, id: 'a' + Digest::SHA2.hexdigest(rand.to_s),
          style: avatar ? '' : (env[:colors][name] ||= HTML.colorize),
          c: avatar ? {_: :img, class: :avatar, src: avatar} : name}.update(avatar ? {class: :avatar} : {}), ' ']
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[SIOC+'MailMessage'] = -> post, env {
      unless env[:query] && env[:query].has_key?('head') && !post[Title] # hide title-less posts in heading mode
        post.delete Type
        uri = post.delete 'uri'
        titles = (post.delete(Title)||[]).map(&:to_s).map(&:strip).uniq
        date = (post.delete(Date) || [])[0]
        from = post.delete(Creator) || []
        to = post.delete(To) || []
        images = post.delete(Image) || []
        content = post.delete(Content) || []
        uri_hash = 'r' + Digest::SHA2.hexdigest(uri)
        {class: :post, id: uri_hash,
         c: [titles.map{|title|
               title = title.to_s.sub(/\/u\/\S+ on /,'')
               unless env[:title] == title
                 env[:title] = title
                 [{_: :a, id: 't' + Digest::SHA2.hexdigest(rand.to_s), class: :title, href: uri, c: CGI.escapeHTML(title)}, ' ']
               end},
             {_: :a, id: 'pt' + uri_hash, class: :id, c: '☚', href: uri},
             ({_: :a, class: :date, id: 'date' + uri_hash, href: ServerAddr + '/' + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date),
             images.map{|i| Markup[Image][i,env]},
             {_: :table, class: :fromTo,
              c: {_: :tr,
                  c: [{_: :td,
                       c: from.map{|f|Markup[Creator][f,env]},
                       class: :from},
                      {_: :td, c: '&rarr;'},
                      {_: :td,
                       c: [to.map{|f|Markup[To][f,env]},
                           post.delete(SIOC+'reply_of')],
                       class: :to}]}},
             content, ((HTML.keyval post, env) unless post.keys.size < 1)]}
      end}

  end
end
