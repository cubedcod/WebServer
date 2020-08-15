%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module URIs

    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).concat(ENV.has_key?('HOSTNAME') ? [ENV['HOSTNAME']] : []).uniq

    # URI -> file path
    def fsPath      ## host part
      (if local_node?
       ''
      else           # host dir
        hostPath
       end) +       ## path part
        (if !path || path =='/' # root node
         %w(index)
        elsif local_node?
          if parts[0] == 'msg'  # Message-ID to path
            id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
            ['mail', id[0..1], id[2..-1]]
          else       # local path
            parts.map{|p| Rack::Utils.unescape_path p}
          end
        elsif path.size > 512 || parts.find{|p|p.size > 127} # long path
          hash = Digest::SHA2.hexdigest [path, query].join
          [hash[0..1], hash[2..-1]]
        else         # direct map to local path
          parts.map{|p| Rack::Utils.unescape_path p}
         end).join('/')
    end

    def hostPath
      host.split('.').-(%w(com net org www)).reverse.join('/') + '/'
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
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def nodeSet
      if node.file?
        [self]
      else
        qs = query_values || {}
        (if node.directory?
         if qs.has_key?('f') && !qs['f'].empty? && path != '/'          # FIND
           `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
         elsif qs.has_key?('find') && !qs['find'].empty? && path != '/' # FIND case-insensitive substring
           `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
         elsif (qs.has_key?('Q') || qs.has_key?('q')) && path != '/'    # GREP
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
           else   # N ordered terms
             cmd = "grep -ril -- #{Shellwords.escape args.join '.*'} #{shellPath}"
           end
           `#{cmd} | head -n 1024`.lines.map &:chomp
         else                              # LS
           env[:summary] = !qs.has_key?('fullContent') # summarize dir entries
           [node, *node.children]
         end
        else
          globPath = fsPath
          unless globPath.match /[\*\{\[]/ # GLOB
            globPath += query_hash if static_node? && !local_node?
            globPath += '.*'               # default document-set
          end
          Pathname.glob globPath
         end).map{|p| # join relative path to URI-space
          join('/' + p.to_s[(local_node? ? 0 : hostPath.size)..-1].gsub(':','%3A').gsub(' ','%20').gsub('#','%23')).R env}
      end
    end

  end
  module HTML

    MarkupGroup[LDP+'Container'] = -> dirs, env {
      if this = dirs.find{|d| d['uri'] == env[:base].uri.split('?')[0]}
        rest = dirs.select{|d| d['uri'] != this['uri']}
        {class: 'main container',
         c: [{_: :span, class: :head, c: this['uri'].R.basename},
             {class: :body,
              c: if env[:view] == 'table'
               HTML.tabular rest, env
             else
               rest.map{|dir| Markup[LDP+'Container'][dir,env]}
              end
             }]}
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
           {style: "display: inline", class: :body, c: HTML.keyval(dir, env)}]}}

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
