%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module URIs

    # filesystem path for URI
    def fsPath      ## host
      (if localNode? # localhost
       ''
      else           # host dir
        hostPath
       end) +       ## path
        (if !path    # no path
         []
        elsif localNode? && parts[0] == 'msg'
          MID2Path[Rack::Utils.unescape_path parts[1]]
        elsif path.size > 512 || parts.find{|p|p.size > 255} # long path, hash it
          hash = Digest::SHA2.hexdigest path
          [hash[0..1], hash[2..-1]]
        else         # direct-map path
          parts.map{|p| Rack::Utils.unescape p}
         end).join('/')
    end

    # filesystem path for hostname
    def hostPath
      host.split('.').-(%w(com net org www)).reverse.join('/') + '/'
    end

    def localNode?
      !host || %w(l localhost).member?(host)
    end

    # local Pathname instance for resource
    def node; Pathname.new fsPath end

    # escaped path for shell invocation
    def shellPath; Shellwords.escape fsPath.force_encoding 'UTF-8' end

  end
  module HTTP

    # respond with graph data from filesystem nodes
    def nodeResponse
      return fileResponse if node.file? # static node hit, nothing to do
      qs = query_values || {}           # query arguments
      timeMeta                          # find temporally-adjacent node pointers
      summarize = !(qs.has_key? 'full') # default to summarize for multi-node requests

      # find node locations on fs
      paths = if node.directory?        # node container
                if qs.has_key?('f') && !qs['f'].empty? && path != '/' # FIND full name (case-insensitive)
                  `find #{shellPath} -iname #{Shellwords.escape qs['f']}`.lines.map &:chomp
                elsif qs.has_key?('find') && !qs['find'].empty? && path != '/'# FIND substring (case-insensitive)
                  `find #{shellPath} -iname #{Shellwords.escape '*' + qs['find'] + '*'}`.lines.map &:chomp
                elsif (qs.has_key?('Q') || qs.has_key?('q')) && path != '/'
                  env[:grep] = true     # GREP
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
                  else # N ordered terms
                    cmd = "grep -ril -- #{Shellwords.escape args.join '.*'} #{shellPath}"
                  end
                  `#{cmd} | head -n 1024`.lines.map &:chomp
                else # container without query
                  if summarize
                    [node] # container listing
                  else     # container contents
                    [node, *node.children]
                  end
                end
              else                      # nodes selected w/ GLOB
                globPath = fsPath
                if uri.match GlobChars  # parametric glob
                  env[:grep] = true if qs.has_key? 'q' # enable grepping within glob results
                else                    # graph-document glob
                  summarize = false
                  globPath += '.*'
                end
                Pathname.glob globPath
              end

      # map fs locations to URI space
      pathIndex = localNode? ? 0 : hostPath.size
      nodes = paths.map{|p|
        ((host ? ('https://' + host) : '') + '/' + p.to_s[pathIndex..-1].gsub(':','%3A').gsub('#','%23')).R env }

      # return node-data in requested format
      if nodes.size==1 && nodes[0].ext == 'ttl' && selectFormat == 'text/turtle'
        nodes[0].fileResponse           # static node ready to go
      else                              # transform/merge graph node(s)
        if summarize
          env[:summary] = true
          nodes = nodes.map &:summary # summary nodes
        end
        nodes.map &:loadRDF             # node -> Graph
        graphResponse                   # HTTP Response
      end
    end
  end
end
