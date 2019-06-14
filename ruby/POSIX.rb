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
      dir.mkdir
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
      puts "access error on #{path}"
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
      (p && !p.empty?) ? `find #{sh} -ipath #{('*'+p+'*').sh} | head -n 2048`.lines.map{|path| POSIX.fromRelativePath path.chomp} : []
    end

    # GLOB(7)
    def glob; (Pathname.glob localPath).map &:R end

    # mapped file
    def node; @node ||= (Pathname.new localPath) end

    def directory?; node.directory? end

    def file?; node.file? end

    # URI -> mapped file(s)
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
           [self, env['REQUEST_PATH'][-1] == '/' ? children : []]
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
      size.do{|sz|
        yield s, Size, sz}
      mtime.do{|mt|
        yield s, Mtime, mt.to_i; yield s, Date, mt.iso8601}
    end

    # file -> RDF
    def triplrImage &f
      yield uri, Type, Image.R
      yield uri, Image, self
      w,h = Dimensions.dimensions localPath
      yield uri, Schema + 'width', w
      yield uri, Schema + 'height', h
    end

    # directory -> RDF
    def triplrContainer
      subject = path[-1] == '/' ? path : (path + '/')
      yield subject, Type, Container.R
      yield subject, Title, basename
      mtime.do{|mt|yield subject, Date, mt.iso8601}
      nodes = children
      nodes.map{|node| yield subject, Contains, node.stripDoc}
      yield subject, Size, nodes.size
    end

  end
  module HTTP

    def fileResponse
      @r ||= {}
      @r[:Response] ||= {}
      @r[:Response]['Access-Control-Allow-Origin'] ||= allowedOrigin
      @r[:Response]['Cache-Control'] ||= 'no-transform' if @r[:Response]['Content-Type'] && @r[:Response]['Content-Type'].match(NoTransform)
      @r[:Response]['Content-Type'] ||= (%w{text/html text/turtle}.member?(mime) ? (mime + '; charset=utf-8') : mime)
      @r[:Response]['ETag'] ||= [uri, mtime, size].join.sha2
      entity @r
    end

  end
  module POSIX
    LinkMethod = :ln
    #LinkMethod = :ln_s
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
