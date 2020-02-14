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
end
