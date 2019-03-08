class WebResource
  module POSIX
    GlobChars = /[\*\{\[]/

    def link n
      send LinkMethod, n unless n.exist?
    rescue Exception => e
      puts e,e.class,e.message
    end

    def ln n
      FileUtils.ln   node.expand_path, n.node.expand_path
    end

    def ln_s n
      FileUtils.ln_s node.expand_path, n.node.expand_path
    end

    def readFile; File.open(localPath).read end

    def lines; e ? (open localPath).readlines.map(&:chomp) : [] end

    def writeFile o
      dir.mkdir
      File.open(localPath,'w'){|f|f << o}
      self
    end

    def touch
      FileUtils.touch localPath
    end

    def size; node.size rescue 0 end

    def mtime; node.stat.mtime end
    alias_method :m, :mtime

    def exist?; node.exist? end
    alias_method :e, :exist?

    def symlink?; node.symlink? end

    def children
      node.children.delete_if{|f|
        f.basename.to_s.index('.')==0
      }.map &:R
    rescue Errno::EACCES
      puts "access error for #{path}"
      []
    end

    # storage usage
    def du; `du -s #{sh}| cut -f 1`.chomp.to_i end

    # make container
    def mkdir
      FileUtils.mkdir_p localPath unless exist?
      self
    end

    # FIND(1)
    def find p
      (p && !p.empty?) ? `find #{sh} -ipath #{('*'+p+'*').sh} | head -n 2048`.lines.map{|_|
                           POSIX.fromRelativePath _.chomp} : []
    end

    # GLOB(7)
    def glob; (Pathname.glob localPath).map &:R end

    # Pathname
    def node; @node ||= (Pathname.new localPath) end
    def directory?; node.directory? end
    def file?; node.file? end

    # WebResource -> file(s) mapping
    def localNodes
      (if directory? # directory
       if q.has_key?('f') && path!='/' # FIND
         found = find q['f']
         found
       elsif q.has_key?('q') && path!='/' # GREP
         grep q['q']
       else # LS
         index = (self+'index.html').glob
         if !index.empty? && qs.empty? # no query and static HTML index-compile exists
           index # static index
         else
           [self, path[-1] == '/' ? children : []]
         end
       end
      else # files
        if match GlobChars # glob
          files = glob || [] # server-wide path
          files.concat ('/' + host + path).R.glob # path on host
        else # default file-set
          files = (self + '.*').glob                # base + extension
          files = (self + '*').glob if files.empty? # prefix-match
        end
        [self, files]
       end).justArray.flatten.compact.uniq.select &:exist?
    end

    def self.splitArgs args
      args.shellsplit
    rescue
      args.split /\W/
    end

  end

  include POSIX

  module Webize

    # file -> RDF
    def triplrFile
      s = path
      yield s, Title, basename
      #size.do{|sz| yield s, Size, sz}
      #mtime.do{|mt| yield s, Mtime, mt.to_i; yield s, Date, mt.iso8601}
    end

    # directory -> RDF
    def triplrContainer
      s = path
      s = s + '/' unless s[-1] == '/'
      yield s, Type, Container.R
      yield s, Title, basename
      #yield s, Size, children.size
      #mtime.do{|mt| yield s, Mtime, mt.to_i; yield s, Date, mt.iso8601}
    end

  end
  module HTTP

    # file -> HTTP Response
    def fileResponse
      @r[:Response]['Access-Control-Allow-Origin'] ||= '*'
      @r[:Response]['Cache-Control'] ||= 'no-transform' if @r[:Response]['Content-Type'] && @r[:Response]['Content-Type'].match(NoTransform)
      @r[:Response]['Content-Type'] ||= (%w{text/html text/turtle}.member?(mime) ? (mime + '; charset=utf-8') : mime)
      @r[:Response]['ETag'] ||= [m,size].join.sha2
      if q.has_key?('preview') && ext && ext.match(/(mp4|mkv|png|jpg)/i)
        filePreview
      else
        entity @r
      end
    end

  end
  module POSIX

    # fs-link capability test
    LinkMethod = begin
                   file = 'cache/test/link'.R
                   link = 'cache/test/link_'.R
                   # reset src-state
                   file.touch unless file.exist?
                   # reset dest-state
                   link.delete if link.exist?
                   # try link
                   file.ln link
                   # hard-link succeeded, return
                   :ln
                 rescue Exception => e
                   # symbolic-link fallback
                   :ln_s
                 end
  end
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
