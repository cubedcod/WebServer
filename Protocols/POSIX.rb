%w(fileutils pathname shellwords).map{|d| require d }
class WebResource

  def dir_triples
    graph = env[:repository] ||= RDF::Repository.new
    subject = self                           # directory URI
    subject += '/' unless subject.to_s[-1] == '/' # enforce trailing-slash on directory name
    graph << RDF::Statement.new(subject, Type.R, (LDP + 'Container').R)
    graph << RDF::Statement.new(subject, Title.R, basename)
    graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
    nodes = node.children
    if nodes.size <= 8
      nodes.map{|child|                      # point to all child-nodes
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename('.ttl').to_s.gsub(' ','%20').gsub('#','%23')))}
    else                                     # abbreviated pointers
      slugs = {}
      nodes.map{|n|
        n.basename('.ttl').to_s.split(/[\W_]/).grep(/^\D/).map{|t|
          slugs[t] ||= 0
          slugs[t] += 1}}
      slugs.select{|s,count| count > 2}.sort_by{|s,c|c}.reverse[0..16].map{|slug,c|
        #puts [a,b].join "\t"
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join '*' + slug + '*'))
      }
    end
  end

  module URIs

    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).concat(ENV.has_key?('HOSTNAME') ? [ENV['HOSTNAME']] : []).uniq

    # URI -> filesystem path (one-way map)
    def fsPath
      [hostDir,                # host container
       if !path || path == '/' # null path
         nil
       elsif local_node?       # local path:
         if parts[0] == 'msg'  # Message-ID -> path
           id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
           ['/mail/', id[0..1], '/', id[2..-1]]
         else                  # direct map
           Rack::Utils.unescape_path path
         end                                   # remote path:
       elsif path.size > 512 || parts.find{|p|p.size > 127} # oversize names -> sharded-hash path
         hash = Digest::SHA2.hexdigest [path, query].join
         ['/', hash[0..1], hash[2..-1]]
       else                                    # direct map
         Rack::Utils.unescape_path path
       end].join
    end

    def hostDir
      if local_node?
        '.'
      else
        host.split('.').-(%w(com net org www)).reverse.join '/'
      end
    end

    def local_node?
      !host || LocalAddress.member?(host)
    end

    # local Pathname instance for resource
    def node; Pathname.new fsPath end

    # escaped path for shell invocation
    def shellPath; Shellwords.escape fsPath.force_encoding 'UTF-8' end

  end

  def readFile; node.exist? ? node.read : nil end

  def writeFile o
    FileUtils.mkdir_p node.dirname
    File.open(fsPath,'w'){|f| f << o }
    self
  end

  module HTTP

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowed_origin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def nodeSet
      if node.file?
        [self]
      else
        qs = query_values || {}
        (if node.directory?
         if qs['f'] && !qs['f'].empty?     # FIND
           #puts ['FIND exact', qs['f'], fsPath].join ' '
           `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
         elsif qs['find'] && !qs['find'].empty? && path != '/' # FIND case-insensitive substring
           #puts ['FIND substring', qs['find'], fsPath].join ' '
           `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
         elsif qs.has_key?('Q') || qs.has_key?('q') # GREP
           #puts [:GREP, fsPath].join ' '
           q = qs['Q'] || qs['q']
           args = q.shellsplit rescue q.split(/\W/)
           case args.size
           when 0
             return []
           when 2 # two unordered terms
             cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -il #{Shellwords.escape args[1]}"
           when 3 # three unordered terms
             cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -il #{Shellwords.escape args[2]}"
           when 4 # four unordered terms
             cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -ilZ #{Shellwords.escape args[2]} | xargs -0 grep -il #{Shellwords.escape args[3]}"
           else   # N ordered term
             cmd = "grep -ril -- #{Shellwords.escape args.join '.*'} #{shellPath}"
           end
           `#{cmd} | head -n 1024`.lines.map &:chomp
         else                          # LS
           env[:summary] = !qs.has_key?('fullContent')
           (path=='/' && local_node?) ? [node] : [node, *node.children]
         end
        else
          globPath = fsPath
          if globPath.match /[\*\{\[]/ # GLOB
            #puts [:GLOB, fsPath].join ' '
          else                         # default document-glob
            globPath += query_hash if static_node? && !local_node?
            globPath += '.*'
          end
          Pathname.glob globPath
         end).map{|p| # join relative path to URI-space
          join(p.to_s[hostDir.size..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}
      end
    end

  end
  module HTML

    MarkupGroup[LDP+'Container'] = -> dirs, env {
      if this = dirs.find{|d| d['uri'] == env[:base].uri.split('?')[0]}
        {class: :container,
         c: [{_: :span, class: :head, c: this['uri'].R.basename},
             {class: :body, c: (HTML.tabular dirs, env)}]}
      else
        dirs.map{|dir| Markup[LDP+'Container'][dir,env]}
      end
    }

    Markup[LDP+'Container'] = -> dir, env {
      uri = dir.delete('uri').R env
      [Type, Title,
       W3 + 'ns/posix/stat#mtime',
       W3 + 'ns/posix/stat#size'].map{|p|dir.delete p}
      {class: :container,
       c: [{_: :a, id: 'container' + Digest::SHA2.hexdigest(rand.to_s), class: :head, href: uri.href, type: :node, c: uri.basename},
           {class: :body, c: HTML.keyval(dir, env)}]}}

    Markup[Stat+'File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons[Stat+'File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

    def htmlGrep
      graph = env[:graph]
      qs = query_values || {}
      q = qs['Q'] || qs['q']
      return unless graph && q
      abbreviated = !qs.has_key?('fullContent')

      # query
      wordIndex = {}
      args = q.shellsplit rescue q.split(/\W/)
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      pattern = /(#{args.join '|'})/i

      # trim graph to matching resources
      graph.map{|k,v|
        graph.delete k unless (k.to_s.match pattern) || (v.to_s.match pattern)}

      # trim content to matching lines
      graph.values.map{|r|
        (r[Content]||r[Abstract]||[]).map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).yield_self{|lines|
          r[Abstract] = lines[0..7].map{|line|
            line.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # mark up matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g})
            }
          } if lines.size > 0
        }
        r.delete Content if abbreviated
      }

      # CSS
      graph['#abstracts'] = {Abstract => [HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})]}
    end

  end
end
