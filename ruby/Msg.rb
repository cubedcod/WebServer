# coding: utf-8
class WebResource
  module Webize

    def triplrTweets
      Nokogiri::HTML.parse(readFile).css('div.tweet').map{|tweet|
        s = Twitter + tweet.css('.js-permalink').attr('href')
        authorName = tweet.css('.username b')[0].inner_text
        author = (Twitter + '/' + authorName).R
        ts = Time.at(tweet.css('[data-time]')[0].attr('data-time').to_i).iso8601
        yield s, Type, Post.R
        yield s, Date, ts
        yield s, Creator, author
        yield s, To, Twitter.R
        content = tweet.css('.tweet-text')[0]
        if content
          content.css('a').map{|a|
            a.set_attribute('id', 'tweetedlink'+rand.to_s.sha2)
            a.set_attribute('href', Twitter + (a.attr 'href')) if (a.attr 'href').match /^\//
            yield s, DC+'link', (a.attr 'href').R}
          yield s, Content, HTML.clean(content.inner_html).gsub(/<\/?span[^>]*>/,'').gsub(/\n/,'').gsub(/\s+/,' ')
        end
        tweet.css('img').map{|img|
          yield s, Image, img.attr('src').to_s.R}}
    end

    IndexHTML['twitter.com'] = :indexTweets

    def indexTweets
      newPosts = []
      graph = {}
      triplrTweets{|s,p,o|
        graph[s] ||= {'uri'=>s}
        graph[s][p] ||= []
        graph[s][p].push o}
      graph.map{|u,r| # visit tweet resource
        r[Date].do{|t|
          # find storage location
          slug = (u.sub(/https?/,'.').gsub(/\W/,'.')).gsub /\.+/,'.'
          time = t[0].to_s.gsub(/[-T]/,'/').sub(':','/').sub /(.00.00|Z)$/, ''
          doc = "/#{time}#{slug}.e".R
          if !doc.e # update cache
            doc.writeFile({u => r}.to_json)
            newPosts << doc
          end}}
      newPosts
    end

    def indexMail
      triples = 0
      triplrMail{|s,p,o|triples += 1}
      puts "    #{triples} triples"
    rescue Exception => e
      puts uri, e.class, e.message
    end

    def indexMails; glob.map &:indexMail end

    def triplrChatLog &f
      linenum = -1
      base = stripDoc
      dir = base.dir
      log = base.uri
      basename = base.basename
      channel = dir + '/' + basename
      day = dir.uri.match(/\/(\d{4}\/\d{2}\/\d{2})/).do{|d|d[1].gsub('/','-')}
      readFile.lines.map{|l|
        l.scan(/(\d\d)(\d\d)(\d\d)[\s+@]*([^\(\s]+)[\S]* (.*)/){|m|
          s = base + '#l' + (linenum += 1).to_s
          yield s, Creator, ('#'+m[3]).R
          yield s, To, channel
          yield s, Content, '<span class="msgbody">' +
                         m[4].hrefs{|p,o|
                             yield s,p,o } +
                         '</span>'
          yield s, Date, day+'T'+m[0]+':'+m[1]+':'+m[2] if day}}

      # logfile
      if linenum > 0
        yield log, Date, mtime.iso8601
        yield log, Title, basename.split('%23')[-1] # channel
        yield log, Size, linenum
      end
    end

    def triplrMail &b
      m = Mail.read node; return unless m
      id = m.message_id || m.resent_message_id || rand.to_s.sha2 # Message-ID
      puts " MID #{id}" if @verbose
      msgURI = -> id { h=id.sha2; ['', 'msg', h[0], h[1], h[2], id.gsub(/[^a-zA-Z0-9]+/,'.')[0..96], '#this'].join('/').R}
      resource = msgURI[id]; e = resource.uri                # Message URI
      puts " URI #{resource}" if @verbose
      srcDir = resource.path.R; srcDir.mkdir # container
      srcFile = srcDir + 'this.msg'          # pathname
      unless srcFile.e
        link srcFile # link canonical-location
        puts "LINK #{srcFile}" if @verbose
      end
      yield e, Identifier, id # Message-ID
      yield e, Type, Email.R

      # HTML body
      htmlFiles, parts = m.all_parts.push(m).partition{|p|p.mime_type=='text/html'}
      htmlCount = 0
      htmlFiles.map{|p| # HTML file
        html = srcDir + "#{htmlCount}.html"  # file location
        yield e, DC+'hasFormat', html        # file pointer
        unless html.e
          html.writeFile p.decoded  # store HTML email
          puts "HTML #{html}" if @verbose
        end
        htmlCount += 1 } # increment count

      # text/plain body
      parts.select{|p|
        (!p.mime_type || p.mime_type == 'text/plain') && # text parts
          Mail::Encodings.defined?(p.body.encoding)      # decodable?
      }.map{|p|
        yield e, Content,
              HTML.render({_: :pre,
                           c: p.decoded.to_utf8.lines.to_a.map{|l| # split lines
                             l = l.chomp # strip any remaining [\n\r]
                             if qp = l.match(/^((\s*[>|]\s*)+)(.*)/) # quoted line
                               depth = (qp[1].scan /[>|]/).size # > count
                               if qp[3].empty? # drop blank quotes
                                 nil
                               else # wrap quotes in <span>
                                 indent = "<span name='quote#{depth}'>&gt;</span>"
                                 {_: :span, class: :quote,
                                  c: [indent * depth,' ',
                                      {_: :span, class: :quoted, c: qp[3].gsub('@','').hrefs{|p,o|yield e, p, o}}]}
                               end
                             else # fresh line
                               [l.gsub(/(\w+)@(\w+)/,'\2\1').hrefs{|p,o|yield e, p, o}]
                             end}.compact.intersperse("\n")})} # join lines

      # recursive messages, digests, forwards, archives..
      parts.select{|p|p.mime_type=='message/rfc822'}.map{|m|
        content = m.body.decoded                   # decode message-part
        f = srcDir + content.sha2 + '.inlined.msg' # message location
        f.writeFile content if !f.e                # store message
        f.triplrMail &b} # triplr on contained message

      # From
      from = []
      m.from.do{|f|
        f.justArray.compact.map{|f|
          noms = f.split ' '
          if noms.size > 2 && noms[1] == 'at'
            f = "#{noms[0]}@#{noms[2]}"
          end
          puts "FROM #{f}" if @verbose 
          from.push f.to_utf8.downcase}} # queue address for indexing + triple-emitting
      m[:from].do{|fr|
        fr.addrs.map{|a|
          name = a.display_name || a.name # human-readable name
          yield e, Creator, name
          puts "NAME #{name}" if @verbose
        } if fr.respond_to? :addrs}
      m['X-Mailer'].do{|m|
        yield e, SIOC+'user_agent', m.to_s
        puts " MLR #{m}" if @verbose
      }

      # To
      to = []
      %w{to cc bcc resent_to}.map{|p|      # recipient fields
        m.send(p).justArray.map{|r|        # recipient
          puts "  TO #{r}" if @verbose
          to.push r.to_utf8.downcase }}    # queue for indexing
      m['X-BeenThere'].justArray.map{|r|to.push r.to_s} # anti-loop recipient
      m['List-Id'].do{|name|yield e, To, name.decoded.sub(/<[^>]+>/,'').gsub(/[<>&]/,'')} # mailinglist name

      # Subject
      subject = nil
      m.subject.do{|s|
        subject = s.to_utf8.gsub(/\[[^\]]+\]/){|l| yield e, Label, l[1..-2] ; nil }
        yield e, Title, subject}

      # Date
      date = m.date || Time.now rescue Time.now
      date = date.to_time.utc
      dstr = date.iso8601
      yield e, Date, dstr
      dpath = '/' + dstr[0..6].gsub('-','/') + '/msg/' # month
      puts "DATE #{date}\nSUBJ #{subject}" if @verbose && subject

      # index addresses
      [*from,*to].map{|addr|
        user, domain = addr.split '@'
        if user && domain
          apath = dpath + domain + '/' + user # address
          yield e, (from.member? addr) ? Creator : To, (apath+'?head').R # To/From triple
          if subject
            slug = subject.scan(/[\w]+/).map(&:downcase).uniq.join('.')[0..63]
            mpath = apath + '.' + dstr[8..-1].gsub(/[^0-9]+/,'.') + slug # time & subject
            mpath = mpath + (mpath[-1] == '.' ? '' : '.')  + 'msg' # file-type extension
            mdir = '../.mail/' + domain + '/' # maildir
            %w{cur new tmp}.map{|c| (mdir + c).R.mkdir} # maildir container
            mloc = (mdir + 'cur/' + id.sha2 + '.msg').R # maildir entry
            iloc = mpath.R # index entry
            [iloc,mloc].map{|loc| loc.dir.mkdir # container
              unless loc.e
                link loc
                puts "LINK #{loc}" if @verbose
              end
            }
          end
        end
      }

      # index bidirectional refs
      %w{in_reply_to references}.map{|ref|
        m.send(ref).do{|rs|
          rs.justArray.map{|r|
            dest = msgURI[r]
            yield e, SIOC+'reply_of', dest
            destDir = dest.path.R; destDir.mkdir; destFile = destDir+'this.msg'
            # bidirectional reference link
            rev = destDir + id.sha2 + '.msg'
            rel = srcDir + r.sha2 + '.msg'
            if !rel.e # link missing
              if destFile.e # link
                destFile.link rel
              else # symlink. it may appear
                destFile.ln_s rel unless rel.symlink?
              end
            end
            srcFile.link rev if !rev.e}}}

      # attachments
      m.attachments.select{|p|Mail::Encodings.defined?(p.body.encoding)}.map{|p| # decodability check
        name = p.filename.do{|f|f.to_utf8.do{|f|!f.empty? && f}} ||                           # explicit name
               (rand.to_s.sha2 + (Rack::Mime::MIME_TYPES.invert[p.mime_type] || '.bin').to_s) # generated name
        file = srcDir + name                     # file location
        unless file.e
          file.writeFile p.body.decoded # store
          puts "FILE #{file}" if @verbose
        end
        yield e, SIOC+'attachment', file         # file pointer
        if p.main_type=='image'                  # image attachments
          yield e, Image, file                   # image link represented in RDF
          yield e, Content,                      # image link represented in HTML
                HTML.render({_: :a, href: file.uri, c: [{_: :img, src: file.uri}, p.filename]}) # render HTML
        end }
    end

    def triplrMbox &b      
    end

  end
end

class WebResource

  module HTML

    Markup[Post] = -> post , env {
      uri = post.uri.justArray[0]
      titles = post.delete(Title).justArray.map(&:to_s).map(&:strip).uniq
      date = post.delete(Date).justArray[0]
      from = post.delete(From).justArray
      to = post.delete(To).justArray
      images = post.delete(Image).justArray
      content = post.delete(Content).justArray
      cache = post.R.cacheFile
      location = if %w{l localhost}.member?(env['SERVER_NAME']) && cache.exist?
                   cache.uri
                 else
                   uri
                 end
      {class: :post,
       c: [titles.map{|title|
             Markup[Title][title,env,uri]},
           images.map{|i|
             Markup[Image][i,env]},
           {_: :table,
            c: {_: :tr,
                c: [{_: :td, c: from.map{|f|Markup[Creator][f,env]}, class: :from},
                    {_: :td, c: '&rarr;'},
                    {_: :td, c: to.map{|f|Markup[Creator][f,env]}, class: :to}]}},
           content,
           {_: :a, id: 't'+rand.to_s.sha2, class: :id, c: '🔗', href: location},
           ((HTML.kv post, env) unless post.empty?),
           (Markup[Date][date] if date),
          ]}}

    # group by sender
    Group['from'] = -> graph { Group['from-to'][graph,Creator] }

    # group by recipient
    Group['to'] = -> graph { Group['from-to'][graph,To] }

    # group by sender or recipient
    Group['from-to'] = -> graph,predicate {
      users = {}
      graph.values.map{|msg|
        msg[predicate].justArray.map{|creator|
          c = creator.to_s
          users[c] ||= {name: c, Type => Container.R, Contains => {}}
          users[c][Contains][msg.uri] = msg }}
      users}

  end
end
