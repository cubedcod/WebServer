# coding: utf-8
%w(fileutils pathname shellwords).map{|d| require d }
class WebResource

  def dir_triples graph
    subject = self                                # directory URI
    subject += '/' unless subject.to_s[-1] == '/' # enforce trailing slash on dirname
    graph << RDF::Statement.new(subject, Type.R, (LDP + 'Container').R)
    graph << RDF::Statement.new(subject, Title.R, basename)
    graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
    nodes = node.children.select{|n|n.basename.to_s[0] != '.'}
    nodes.map{|child|                             # point to contained nodes
      graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename.to_s.gsub(' ','%20').gsub('#','%23')))}
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
      q = env[:qs]['q'].to_s
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
      [:links,:qs].map{|e| env[e] ||= {}}
      local = local_node? || offline?
      f    = env[:qs]['f']    && !env[:qs]['f'].empty?
      find = env[:qs]['find'] && !env[:qs]['find'].empty? 
      grep = env[:qs]['q']    && !env[:qs]['q'].empty?
      pathbase = host_parts.join('/').size

      nodes = (if local && node.directory? && (f || find || grep) # search directory
               if f                                               # FIND exact
                 summarize = !env[:fullContent]
                 `find #{Shellwords.escape fsPath} -iname #{Shellwords.escape env[:qs]['f']}`.lines.map &:chomp
               elsif find                                         # FIND substring
                 summarize = !env[:fullContent]
                 `find #{Shellwords.escape fsPath} -iname #{Shellwords.escape '*' + env[:qs]['find'] + '*'}`.lines.map &:chomp
               elsif grep                                         # GREP
                 nodeGrep
               end
              else
                globPath = fsPath
                if globPath.match?(GlobChars) && local
                  if grep
                    glob = Pathname.glob globPath
                    puts "glob too large - dropping #{glob.size - 2048} results"
                    nodeGrep glob[0..2047]                        # GREP in GLOB
                  else
                    Pathname.glob globPath                        # arbitrary GLOB
                  end
                else                                              # default-set GLOB
                  globPath += '*'
                  Pathname.glob globPath
                end
               end).map{|p|                                       # resolve relative-to-host path to full URI
        join(p.to_s[pathbase..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}

      if summarize
        env[:links][:down] = HTTP.qs env[:qs].merge({'fullContent' => nil})
        nodes.map &:preview
      else
        nodes
      end
    end
  end
end
