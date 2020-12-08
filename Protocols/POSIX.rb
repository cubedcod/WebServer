# coding: utf-8

%w(fileutils pathname shellwords).map{|d| require d }
class WebResource

  def dir_triples graph
    subject = self                           # directory URI
    subject += '/' unless subject.to_s[-1] == '/' # enforce trailing-slash on directory name
    graph << RDF::Statement.new(subject, Type.R, (LDP + 'Container').R)
    graph << RDF::Statement.new(subject, Title.R, basename)
    graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
    nodes = node.children.select{|n|n.basename.to_s[0] != '.'}
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
         elsif path[-1] == '🐢'
           '/cache' + Rack::Utils.unescape_path(path)
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

    # URI -> pathnames
    def nodeGrep files = nil
      files = [fsPath] if !files || files.empty?
      qs = query_values || {}
      q = qs['Q'] || qs['q']
      args = q.shellsplit rescue q.split(/\W/)
      file_arg = files.map{|file| Shellwords.escape file.to_s }.join ' '
      case args.size
      when 0
        return []
      when 2 # two unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -il #{Shellwords.escape args[1]}"
      when 3 # three unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -il #{Shellwords.escape args[2]}"
      when 4 # four unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{file_arg} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -ilZ #{Shellwords.escape args[2]} | xargs -0 grep -il #{Shellwords.escape args[3]}"
      else   # N ordered term
        cmd = "grep -ril -- #{Shellwords.escape args.join '.*'} #{file_arg}"
      end
      `#{cmd} | head -n 1024`.lines.map &:chomp
    end

    # URI -> nodes
    def nodeSet
      if node.file?
        [self]
      else
        qs = query_values || {}
        (if node.directory?
         if qs['f'] && !qs['f'].empty? # FIND
           `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
         elsif qs['find'] && !qs['find'].empty? && path != '/' # FIND case-insensitive substring
           `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
         elsif qs.has_key?('Q') || qs.has_key?('q') # GREP directory
           nodeGrep
         else                          # LS
           env[:summary] = !qs.has_key?('fullContent')
           (path=='/' && local_node?) ? [node] : [node, *node.children.select{|n|n.basename.to_s[0] != '.'}]
         end
        else
          globPath = fsPath
          if globPath.match GlobChars
            if qs.has_key?('Q') || qs.has_key?('q')
              nodeGrep Pathname.glob globPath # GREP within GLOB
            else
              Pathname.glob globPath # parametric GLOB
            end
          else # default document GLOB
            globPath += query_hash if static_node? && !local_node?
            globPath += '.*'
            Pathname.glob globPath
          end
         end).map{|p| # join path to URI-space
          join(p.to_s[hostDir.size..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env
        }
      end
    end

  end
  module HTML

    MarkupGroup[LDP+'Container'] = -> dirs, env {
      if env[:view] == 'table'
        HTML.tabular dirs, env
      else
        dirs.map{|d|
          Markup[LDP+'Container'][d, env]}
      end}

    Markup[LDP+'Container'] = -> dir, env {
      uri = (dir.delete('uri') || env[:base]).R env
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

  end
end
