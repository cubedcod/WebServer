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
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename.to_s.gsub(' ','%20').gsub('#','%23')))}
    else                                     # abbreviated pointers
      slugs = {}
      nodes.map{|n|
        n.basename.to_s.split(/[\W_]/).grep(/^\D/).map{|t|
          slugs[t] ||= 0
          slugs[t] += 1}}
      slugs.select{|s,count| count > 2}.sort_by{|s,c|c}.reverse[0..16].map{|slug,c|
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join '*' + slug + '*'))
      }
    end
  end

  module URIs

    # URI -> path (String)
    def fsPath
      [host_parts,            # host directory
       if local_node?         # local path
         if parts[0] == 'msg' # Message-ID -> sharded message storage
           id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
           ['mail', id[0..1], id[2..-1]]
         else                 # direct mapping
           parts.map{|part| Rack::Utils.unescape_path part}
         end
       else                   # remote path - qs differentiates local storage path
         ps = if (path && path.size > 496) || parts.find{|p|p.size > 127} # oversized, hash and shard
                hash = Digest::SHA2.hexdigest path
                [hash[0..1], hash[2..-1]]
              else            # direct mapping
                parts.map{|part| Rack::Utils.unescape_path part}
              end
         if query                            # querystring exists
           qh = Digest::SHA2.hexdigest(query)[0..15] # hash query
           if ps.size > 0
             name = ps.pop                   # get basename
             x = File.extname name           # find extension
             base = File.basename name, x    # strip extension
             ps.push [base, '.', qh, x].join # basename w/ queryhash before extension
           else
             ps.push qh                      # queryhash as basename
           end
         end
         ps
       end].join '/'
    end

    # URI -> Pathname
    def node; Pathname.new fsPath end

  end

  def readFile; node.exist? ? node.read : nil end

  def writeFile o
    FileUtils.mkdir_p node.dirname
    File.open(fsPath,'w'){|f| f << o }
    self
  end

  module HTTP

    # URI -> pathnames
    def nodeGrep files = nil
      files = [fsPath] if !files || files.empty?
      qs = queryvals
      q = (qs['Q'] || qs['q']).to_s
      return [] if q.empty?
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
      qs = queryvals

      # glob-chars and grep-arg only magic on offline local cache
      do_local_searches = local_node? || offline?
      do_grep = (qs.has_key?('Q')||qs.has_key?('q')) && do_local_searches

      summarize = qs.has_key? 'abbr'
      nodes = if node.file? # direct map - single node
                [self]
              else          # indirect map - one or more nodes
                pathbase = host_parts.join('/').size
                (if node.directory?                                    # directory
                 if qs['f'] && !qs['f'].empty?                         # FIND - full match
                   `find #{Shellwords.escape fsPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
                 elsif qs['find'] && !qs['find'].empty? && path != '/' # FIND - substring match
                   `find #{Shellwords.escape fsPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
                 elsif do_grep                                         # GREP
                   nodeGrep
                 else                                                  # LS
                   summarize = true
                   env[:links][:down] ||= '*'
                   (path=='/' && local_node?) ? [node] : [node, *node.children.select{|n|n.basename.to_s[0] != '.'}]
                 end
                else                                                   # file(s)
                  globPath = fsPath
                  if globPath.match?(GlobChars) && do_local_searches
                    if do_grep
                      nodeGrep Pathname.glob globPath                  # GREP
                    else
                      Pathname.glob globPath                           # GLOB
                    end
                  else                                                 # default-set GLOB
                    globPath += '.*'
                    Pathname.glob globPath
                  end
                 end).map{|p|join(p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env} # escape reserved-chars and resolve path to URI
              end
      summarize ? nodes.map(&:summary) : nodes
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
       c: [{_: :a, id: 'container' + Digest::SHA2.hexdigest(rand.to_s), class: :head, href: uri.href, c: uri.basename},
           {class: :body, c: HTML.keyval(dir, env)}]}}

    Markup[Stat+'File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons[Stat+'File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

  end
end
