class WebResource
  module POSIX
    def basename; File.basename( path || '/' ) end                      # BASENAME(1)
    def dir; dirname.R env if path end                                  # DIRNAME(1)
    def dirname; File.dirname path if path end                          # DIRNAME(1)
    def exist?; node.exist? end
    def ext; File.extname( path || '' )[1..-1] || '' end
    def find p; `find #{shellPath} -iname #{Shellwords.escape p}`.lines.map{|p| ('/' + p.chomp).R } end # FIND(1)
    def fsPath; (hostpath + (path || '/')).R env end
    def glob; Pathname.glob(relPath).map{|p| ('/' + p.to_s).R env } end # GLOB(7)
    def hostname; env && env['SERVER_NAME'] || host || 'localhost' end
    def hostpath; '/' + hostname.split('.').-(%w(com net org www)).reverse.join('/') end
    def mkdir; FileUtils.mkdir_p relPath unless exist?; self end        # MKDIR(1)
    def node; Pathname.new relPath end
    def parts; path ? path.split('/').-(['']) : [] end
    def relFrom source; node.relative_path_from source.node end
    def relPath; ['/', '', nil].member?(path) ? '.' : (path[0] == '/' ? path[1..-1] : path) end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def write o; dir.mkdir; File.open(relPath,'w'){|f|f << o.force_encoding('UTF-8')}; self end
  end
  include POSIX
end
