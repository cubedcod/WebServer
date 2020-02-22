%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module URIs

    # URI -> file path
    def fsPath      ## host
      (if localNode? # localhost
       ''
      else           # host dir
        hostPath
       end) +       ## path
        (if !path    # no path
         []
        elsif localNode? && parts[0] == 'msg' # message-ID URL
          id = Digest::SHA2.hexdigest Rack::Utils.unescape_path parts[1]
          ['mail', id[0..1], id[2..-1]]       # mail storage-path
        elsif path.size > 512 || parts.find{|p|p.size > 255}
          hash = Digest::SHA2.hexdigest path  # path too big, hash it
          [hash[0..1], hash[2..-1]]
        else                                  # direct path
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
    File.open(fsPath,'w'){|f|f << o.force_encoding('UTF-8')}
    self
  end

  module HTTP

    # return lazily-generated File or String, via Rack file-handler if File, if needed by client
    def entity generator = nil
      entities = env['HTTP_IF_NONE_MATCH']&.strip&.split /\s*,\s*/
      if entities && entities.include?(env[:resp]['ETag'])
        [304, {}, []]                            # unmodified
      else
        body = generator ? generator.call : self # generate
        if body.class == WebResource             # resource reference
          Rack::Files.new('.').serving(Rack::Request.new(env), body.fsPath).yield_self{|s,h,b|
            if 304 == s
              [304, {}, []]                      # unmodified dereference
            else
              h['Content-Type'] = 'application/javascript; charset=utf-8' if h['Content-Type'] == 'application/javascript'
              env[:resp]['Content-Length'] = body.node.size.to_s
              [s, h.update(env[:resp]), b]       # file
            end}
        else
          env[:resp]['Content-Length'] = body.bytesize.to_s
          [200, env[:resp], [body]] # generated entity
        end
      end
    end

    def fileResponse
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp]['ETag'] ||= Digest::SHA2.hexdigest [uri, node.stat.mtime, node.size].join
      entity
    end

    def nodeSet
      pathIndex = localNode? ? 0 : hostPath.size
      qs = query_values || {}                                # query arguments
      env[:summary] = !(qs.has_key? 'full')                  # summarize multi-node sets by default
      (if node.directory?
       if qs.has_key?('f') && !qs['f'].empty? && path != '/' # FIND full name (case-insensitive)
         `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
       elsif qs.has_key?('find') && !qs['find'].empty? && path != '/'# FIND substring (case-insensitive)
         `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
       elsif (qs.has_key?('Q') || qs.has_key?('q')) && path != '/'
         env[:grep] = true                                   # GREP
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
        if uri.match GlobChars  # parametric glob
          env[:grep] = true if qs.has_key? 'q' # enable grep within glob
        else                    # base-URI glob
          env[:summary] = false # default graph - show full content
          globPath += '*'
        end
        Pathname.glob globPath
       end).map{|p|             # bind paths to URI-space
        ((host ? ('https://' + host) : '') + '/' + p.to_s[pathIndex..-1].gsub(':','%3A').gsub('#','%23')).R env }
    end

    def nodeResponse
      return fileResponse if StaticFormats.member?(ext.downcase) && node.file? # direct node hit
      nodes = nodeSet                                                          # find indirect nodes
      if nodes.size == 1 && (StaticFormats.member?(nodes[0].ext) || (selectFormat == 'text/turtle' && nodes[0].ext == 'ttl'))
        nodes[0].fileResponse           # single node w/ no merging or transcoding
      else                              # transform and/or merge nodes
        nodes = nodes.map &:summary if env[:summary] # summarize nodes
        nodes.map &:loadRDF             # node(s) -> Graph
        timeMeta                        # reference temporally-adjacent nodes
        graphResponse                   # HTTP Response
      end
    end
  end
end
