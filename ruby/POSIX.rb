%w(digest/sha2 fileutils pathname shellwords).map{|_| require _}
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
    def mkdir; FileUtils.mkdir_p relPath unless exist?; self end           # MKDIR(1)
    def node; @node ||= (Pathname.new relPath) end
    def parts; path ? path.split('/').-(['']) : [] end
    def relPath; URI.unescape(['/','','.',nil].member?(path) ? '.' : (path[0]=='/' ? path[1..-1] : path)) end
    def self.path p; ('/' + p.to_s.chomp.gsub(' ','%20').gsub('#','%23')).R end
    def self.splitArgs args; args.shellsplit rescue args.split /\W/ end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def touch; dir.mkdir; FileUtils.touch relPath end                      # TOUCH(1)
    def writeFile o; dir.mkdir; File.open(relPath,'w'){|f|f << o}; self end

    def fsStat graph, options = {}                                         # STAT(1)
      subject = (options[:base_uri] || path).R
      if node.directory?
        subject = subject.path[-1] == '/' ? subject : (subject + '/') # normalize trailing-slash
        #graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#BasicContainer').R)
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Container').R)
        #if env && subject.path == env['REQUEST_PATH'] # children of request-container
          children.map{|child|
            graph << (RDF::Statement.new subject, (W3+'ns/ldp#contains').R, child.node.directory? ? (child+'/') : child)}
        #end
      else
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/posix/stat#File').R)
      end
      #graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Resource').R)
      graph << (RDF::Statement.new subject, Title.R, basename)
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)
      mtime = node.stat.mtime
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#mtime').R, mtime.to_i)
      graph << (RDF::Statement.new subject, Date.R, mtime.iso8601)
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

    # URI -> file(s)
    def nodes
      (if node.directory?
       if q.has_key?('f') && path!='/'    # FIND
         find q['f'] unless q['f'].empty?
       elsif q.has_key?('q') && path!='/' # GREP
         grep q['q']
       else
         index = (self + 'index.{html,ttl}').R.glob
         if !index.empty? && qs.empty?    # static index
           [index]
         else
           [self, children]               # LS
         end
       end
      else                                # GLOB
        if uri.match /[\*\{\[]/           #  parametric glob
          glob
        else                              #  basic glob
          files = (self + '.*').R.glob    #   base + extension match
          files = (self + '*').R.glob if files.empty? # prefix match
          [self, files]
        end
       end).flatten.compact.uniq.select &:exist?
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
