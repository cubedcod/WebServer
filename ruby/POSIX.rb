class WebResource
  module POSIX
    include URIs

    def basename; File.basename ( path || '/' ) end                        # BASENAME(1)
    def children; node.children.delete_if{|f|f.basename.to_s.index('.')==0}.map &:R end
    def dir; dirname.R if path end                                         # DIRNAME(1)
    def dirname; File.dirname path if path end                             # DIRNAME(1)
    def du; `du -s #{shellPath}| cut -f 1`.chomp.to_i end                  # DU(1)
    def exist?; node.exist? end
    def ext; File.extname( path || '' )[1..-1] || '' end
    def file?; node.file? end
    def find p; `find #{shellPath} -iname #{Shellwords.escape p}`.lines.map{|p|POSIX.path p} end # FIND(1)
    def glob; (Pathname.glob relPath).map &:R end                          # GLOB(7)
    def ln   n; FileUtils.ln   node.expand_path, n.node.expand_path end    # LN(1)
    def ln_s n; FileUtils.ln_s node.expand_path, n.node.expand_path end    # LN(1)
    def link n; n.dir.mkdir; send :ln, n unless n.exist? end               # LN(1)
    def lines; exist? ? (open relPath).readlines.map(&:chomp) : [] end
    def mkdir; FileUtils.mkdir_p relPath unless exist?; self end           # MKDIR(1)
    def node; @node ||= (Pathname.new relPath) end
    def parts; path ? path.split('/').-(['']) : [] end
    def relPath; URI.unescape(path == '/' ? '.' : (path[0] == '/' ? path[1..-1] : path)) end
    def self.path p; ('/' + p.to_s.chomp.gsub(' ','%20').gsub('#','%23')).R end
    def self.splitArgs args; args.shellsplit rescue args.split /\W/ end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def stripDoc; uri.sub(/\.(html|json|md|ttl|txt)$/,'').R end
    def touch; dir.mkdir; FileUtils.touch relPath end                      # TOUCH(1)
    def writeFile o; dir.mkdir; File.open(relPath,'w'){|f|f << o}; self end

    # STAT(1) fs metadata -> RDF::Graph
    def fsMeta graph, options = {}
      subject = options[:base_uri]&.R || self
      if node.directory?
        subject = subject.path[-1] == '/' ? subject : (subject + '/') # ensure trailing-slash on container URI
        graph << (RDF::Statement.new subject, Type.R, (W3 + 'ns/ldp#Container').R)
      else
        graph << (RDF::Statement.new subject, Type.R, (W3 + 'ns/posix/stat#File').R)
      end
      graph << (RDF::Statement.new subject, Title.R, basename)
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)
      graph << (RDF::Statement.new subject, Date.R, node.stat.mtime.iso8601)
    end

    # GREP(1)
    def grep q
      env[:grep] = true
      args = POSIX.splitArgs q
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
        pattern = args.join '.*'
        cmd = "grep -ril #{Shellwords.escape pattern} #{shellPath}"
      end
      `#{cmd} | head -n 1024`.lines.map{|path|POSIX.path path}
    end
  end
  include POSIX
end

class Pathname
  def R env = nil
    if env
     (WebResource::POSIX.path self).env env
    else
      WebResource::POSIX.path self
    end
  end
end
