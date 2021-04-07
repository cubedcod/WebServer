module Webize
  module Plaintext

    class Reader

      def chat_triples

        # irssi:
        #  /set autolog on
        #  /set autolog_path ~/web/%Y/%m/%d/%H/$tag.$0.irc
        # weechat:
        #  /set logger.mask.irc "%Y/%m/%d/%H/$server.$channel.irc"

        type = (SIOC + 'InstantMessage').R
        dirname = File.dirname @base.path
        network, channame = @base.basename.split '.'
        channame = Rack::Utils.unescape_path(channame).gsub('#','')
        chan = ('#' + channame).R
        day = @base.parts[0..2].join('-') + 'T'
        hourslug = @base.parts[0..3].join
        lines = 0
        ts = {}
        @doc.lines.grep(/^[^-]/).map{|msg|
          tokens = msg.split /\s+/
          time = tokens.shift
          if ['*','-!-'].member? tokens[0] # actions, joins, parts
            nick = tokens[1]
            msg = tokens[2..-1].join ' '
            msg = '/me ' + msg if tokens[0] == '*'
          elsif tokens[0].match? /^-.*:.*-$/ # notices
            nick = tokens[0][1..tokens[0].index(':')-1]
            msg = tokens[1..-1].join ' '
          elsif re = msg.match(/<[\s@+*]*([^>]+)>\s?(.*)?/)
            nick = re[1]
            msg = re[2]
          end
          nick = CGI.escape(nick || 'anonymous')
          timestamp = day + time
          subject = '#' + channame + hourslug + (lines += 1).to_s
          yield subject, Type, type
          ts[timestamp] ||= 0
          yield subject, Date, [timestamp, '%02d' % ts[timestamp]].join('.')
          ts[timestamp] += 1
          yield subject, To, chan
          creator = (dirname + '/*irc?q=' + nick + '&sort=date&view=table#' + nick).R
          yield subject, Creator, creator
          yield subject, Content, ['<pre>',
                                   msg.hrefs{|p,o| yield '#IRClinks', p, o},
                                   '</pre>'].join if msg}
      end

      def twtxt_triples
        dirname = File.dirname @base.path
        @doc.lines.grep(/^[^#]/).map{|line|
          date, msg = line.split /\t/
          graph = @base.join (dirname == '/' ? '' : dirname) + '/twtxt.' + date.gsub(/\D/,'.')
          subject = graph.join '#msg'
          yield subject, Type, Post.R, graph
          yield subject, Date, date, graph
          yield subject, Content, Webize::HTML.format(msg.hrefs, @base), graph if msg
          yield subject, Creator, (@base.host + dirname).split(/\W/).join('.'), graph
          yield subject, To, @base, graph
        }
      end
    end
  end
end
class WebResource
  module HTML
    MarkupGroup[SIOC+'InstantMessage'] = -> msgs, env {
      msgs.group_by{|p|(p[To] || [''.R])[0]}.map{|to, msgs|
        msgs.map{|msg| msg.delete To}
        {class: :container,
         c: [{class: :head, c: to.R.display_name, _: :a, href: to},
             {class: :body, c: (HTML.tabular msgs, env)}]}
      }}
  end
end
