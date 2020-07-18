%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module URIs

    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).concat(ENV.has_key?('HOSTNAME') ? [ENV['HOSTNAME']] : []).uniq

    # URI -> file path
    def fsPath      ## host part
      (if localNode? # localhost
       ''
      else           # host dir
        hostPath
       end) +       ## path part
        (if !path || path =='/' # root dir
         %w(index)
        elsif localNode?
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

    def localNode?
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
      pathIndex = localNode? ? 0 : hostPath.size
      qs = query_values || {}                      # query arguments
      env[:summary] = !(qs.has_key? 'fullContent') # summarize multi-node sets
      (if node.directory?
       if qs.has_key?('f') && !qs['f'].empty? && path != '/'          # FIND (case-insensitive)
         `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
       elsif qs.has_key?('find') && !qs['find'].empty? && path != '/' #  substring (case-insensitive)
         `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
       elsif (qs.has_key?('Q') || qs.has_key?('q')) && path != '/'    # GREP
         env[:summary] = false # keep full content for HTML highlighting of matched fields
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
       else                     # LS
         [node, *node.children]
       end
      else                      # GLOB
        globPath = fsPath
        unless globPath.match GlobChars # parametric glob
          env[:summary] = false         # glob of default documents
          globPath += query_hash
          globPath += '*'
        end
        Pathname.glob globPath
       end).map{|p|             # map path to URI-space
        (((host && host != 'localhost') ? ('https://' + host) : '') + '/' + p.to_s[pathIndex..-1].gsub(':','%3A').gsub('#','%23')).R env }
    end

  end
end
