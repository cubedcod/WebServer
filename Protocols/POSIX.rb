%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module POSIX

    # filesystem storage-path for resource
    def fsPath                                             ## host
      (if !host || %w(l localhost).member?(host)             # localhost at pwd
       '.'
      else                                                   # host directory
        host.split('.').-(%w(com net org www)).reverse.join('/')
       end) +                                               ## path
        (if !path                                            # no path
         ''
        elsif path.size > 512 || parts.find{|p|p.size > 127} # long path, hash it
          hash = Digest::SHA2.hexdigest path
          ['',hash[0..1],hash[2..-1]].join '/'
        else                                                 # directly-mapped path
          path
         end)
    end

    # glob-pattern results mapped to URI space
    def glob
      Pathname.glob(fsPath).map{|match| join(match.relative_path_from node.dirname).R env}
    end

    # Pathname instance (for convenience)
    def node; Pathname.new fsPath end

    # escaped path for use in shell invocations
    def shellPath; Shellwords.escape fsPath.force_encoding 'UTF-8' end

  end
  include POSIX
end
