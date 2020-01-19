%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module POSIX
    def basename; File.basename path end
    def ext; File.extname(path)[1..-1] || '' end
    def fsPath
      host.split('.').-(%w(com net org www)).reverse.join('/') +
        (if !path
          '/'
         elsif path.size > 512 || parts.find{|p|p.size > 127}
          hash = Digest::SHA2.hexdigest path
          ['',hash[0..1],hash[2..-1]].join '/'
         else
          path
         end)
    end
    def glob
      Pathname.glob(fsPath).map{|p|join p.relative_path_from fsPath}
    end
    def node; Pathname.new fsPath end
    def parts; path ? (path.split('/') - ['']) : [] end
    def shellPath; Shellwords.escape fsPath.force_encoding 'UTF-8' end
    def write o
      FileUtils.mkdir_p node.dirname
      File.open(fsPath,'w'){|f|f << o.force_encoding('UTF-8')}
      self
    end
  end
  include POSIX
end
