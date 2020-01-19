%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module POSIX
    def fsPath
      (if !host || %w(l localhost).member?(host)
       '.'
      else
        host.split('.').-(%w(com net org www)).reverse.join('/')
       end) +
        (if !path
         ''
        elsif path.size > 512 || parts.find{|p|p.size > 127}
          hash = Digest::SHA2.hexdigest path
          ['',hash[0..1],hash[2..-1]].join '/'
        else
          path
         end)
    end
    def glob
      Pathname.glob(fsPath).map{|p|
        #join(p.relative_path_from fsPath).R env
        join(p.relative_path_from node.dirname).R env
      }
    end
    def node; Pathname.new fsPath end
    def shellPath; Shellwords.escape fsPath.force_encoding 'UTF-8' end
    def write o
      FileUtils.mkdir_p node.dirname
      File.open(fsPath,'w'){|f|f << o.force_encoding('UTF-8')}
      self
    end
  end
  include POSIX
end
