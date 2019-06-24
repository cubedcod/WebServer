class WebResource
  module POSIX
    GlobChars = /[\*\{\[]/
    LinkMethod = :ln#_s

    def children
      node.children.delete_if{|f| f.basename.to_s.index('.')==0}.map &:R
    end

    def directory?; node.directory? end

    # DU(1)
    def du; `du -s #{sh}| cut -f 1`.chomp.to_i end

    def exist?; node.exist? end
    alias_method :e, :exist?

    def file?; node.file? end

    # FIND(1)
    def find p
      (p && !p.empty?) ? `find #{sh} -ipath #{('*'+p+'*').sh} | head -n 2048`.lines.map{|path| POSIX.fromRelativePath path.chomp} : []
    end

    # GLOB(7)
    def glob; (Pathname.glob relPath).map &:R end

    # GREP(1)
    def grep q
      env[:grep] = true
      args = POSIX.splitArgs q
      case args.size
      when 0
        return []
      when 2 # two unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -il #{args[1].sh}"
      when 3 # three unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -il #{args[2].sh}"
      when 4 # four unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -ilZ #{args[2].sh} | xargs -0 grep -il #{args[3].sh}"
      else # N ordered terms
        pattern = args.join '.*'
        cmd = "grep -ril #{pattern.sh} #{sh}"
      end
      `#{cmd} | head -n 1024`.lines.map{|path|
        POSIX.fromRelativePath path.chomp}
    end

    # LN(1)
    def ln   n; FileUtils.ln   node.expand_path, n.node.expand_path end
    def ln_s n; FileUtils.ln_s node.expand_path, n.node.expand_path end
    def link n; n.dir.mkdir; send LinkMethod, n unless n.exist? end

    def lines; e ? (open relPath).readlines.map(&:chomp) : [] end

    # MKDIR(1)
    def mkdir
      FileUtils.mkdir_p relPath unless exist?
      self
    end

    def mtime; node.stat.mtime end
    alias_method :m, :mtime

    # URI -> file
    def node; @node ||= (Pathname.new relPath) end

    # URI -> file(s)
    def nodes
      (if directory? # directory
       if q.has_key?('f') && path!='/' # FIND
         found = find q['f']
         found
       elsif q.has_key?('q') && path!='/' # GREP
         grep q['q']
       else # LS
         index = (self+'index.html').glob
         if !index.empty? && qs.empty? # static index-file exists and no query
           index
         else
           children
         end
       end
      else # files
        if uri.match GlobChars # glob
          files = glob
        else # default glob
          files = (self + '.*').glob                # base + extension
          files = (self + '*').glob if files.empty? # prefix match
        end
        [self, files]
       end).justArray.flatten.compact.uniq.select &:exist?
    end

    def readFile; File.open(relPath).read end

    def size; node.size rescue 0 end

    def self.splitArgs args
      args.shellsplit
    rescue
      args.split /\W/
    end

    def symlink?; node.symlink? end

    # TOUCH(1)
    def touch
      dir.mkdir
      FileUtils.touch relPath
    end

    def writeFile o
      dir.mkdir
      File.open(relPath,'w'){|f|f << o}
      self
    end

  end
  include POSIX
end

class Pathname
  def R env=nil
    if env
     (WebResource::POSIX.fromRelativePath to_s.force_encoding 'UTF-8').environment env
    else
      WebResource::POSIX.fromRelativePath to_s.force_encoding 'UTF-8'
    end
  end
end

class String
  def sh; Shellwords.escape self end
end
