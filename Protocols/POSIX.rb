%w(fileutils pathname shellwords).map{|d| require d }
class WebResource
  module POSIX
    def basename; File.basename( path || '/' ) end                      # BASENAME(1)
    def dir; dirname.R env if path end                                  # DIRNAME(1)
    def dirname; File.dirname path if path end                          # DIRNAME(1)
    def ext; File.extname( path || '' )[1..-1] || '' end
    # host + path -> local-storage path
    def fsPath
      (hostpath + if !path
       '/'
      elsif path.size > 512 || parts.find{|p|p.size > 127}
        hash = Digest::SHA2.hexdigest path
        ['',hash[0..1],hash[2..-1]].join '/'
      else
        path
       end).R env
    end
    def glob; Pathname.glob(relPath).map{|p| ('/' + p.to_s).R env } end # GLOB(7)
    def hostname; env && env['SERVER_NAME'] || host || 'localhost' end
    def hostpath; '/' + hostname.split('.').-(%w(com net org www)).reverse.join('/') end
    def mkdir; FileUtils.mkdir_p relPath unless node.exist?; self end        # MKDIR(1)
    def node; Pathname.new relPath end
    def parts; path ? path.split('/').-(['']) : [] end
    def relFrom source; node.relative_path_from source.node end
    def relPath; ['/', '', nil].member?(path) ? '.' : (path[0] == '/' ? path[1..-1] : path) end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def write o; dir.mkdir; File.open(relPath,'w'){|f|f << o.force_encoding('UTF-8')}; self end
  end
  include POSIX
end
