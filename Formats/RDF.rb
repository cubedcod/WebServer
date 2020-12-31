# coding: utf-8
require 'taglib'
class WebResource

  # file -> Repository
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    if node.file?
      unless ['🐢','ttl'].member? ext                     # file metadata
        stat = node.stat
        graph << RDF::Statement.new(self, Title.R, Rack::Utils.unescape_path(basename))
        graph << RDF::Statement.new(self, Date.R, stat.mtime.iso8601)
        graph << RDF::Statement.new(self, (Stat + 'size').R, stat.size)
      end
      if %w(pack part svg ytdl).member? ext
      elsif %w(mp4 mkv webm).member? ext
        graph << RDF::Statement.new(self, Type.R, Video.R) # video-file metadata
      elsif %w(m4a mp3 ogg opus wav).member? ext           # audio-file metadata
        tag_triples graph
      else # read w/ RDF::Reader
        options = {}
        options[:base_uri] = self
        # format hints
        if format = if ext != 'ttl' && (basename.index('msg.') == 0 || path.index('/sent/cur') == 0) # email procmail PREFIX or maildir containment
                   :mail
                 elsif ext.match? /^html?$/
                   :html
                 elsif %w(changelog license readme todo).member?(basename.downcase) || ext == 'txt'
                   :plaintext
                 elsif %w(gemfile makefile rakefile).member? basename.downcase
                   :sourcecode
                 elsif %w(ttl 🐢).member? ext
                   :turtle
                    end
        elsif ext.empty? # no extension. ask FILE(1)
          mime = `file -b --mime-type #{shellPath}`.chomp
          format = :plaintext if mime == 'text/plain'
          options[:content_type] = mime # format from FILE(1)
        elsif mime = named_format
          options[:content_type] = mime # format from extension
        end
        file = fsPath
        if file.index '#'
          (format ? RDF::Reader.for(format) : RDF::Reader.for(**options)).new(File.open(file).read, **options){|_|graph << _} # load path
        else
          options[:format] = format if format
          graph.load 'file:' + file, **options # load fileURI
        end
      end
    elsif node.directory?                     # directory
      dir_triples graph
    end
    self
  end

  # Repository -> file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]                                           # repository to store
    (repository || env[:repository]).each_graph.map{|graph|                                     # graph
      graphURI = (graph.name || self).R                                                         # graph URI
      fsBase = graphURI.fsPath                                                                  # storage path
      fsBase += '/index' if fsBase[-1] == '/'
      f = fsBase + '.ttl'
      unless File.exist? f
        FileUtils.mkdir_p File.dirname f
        RDF::Writer.for(:turtle).open(f){|f|f << graph}                                         # write 🐢
        puts "\e[32m#{'%2d' % graph.size}⋮🐢 \e[1m#{'http://localhost:8000' if !graphURI.host}#{graphURI}\e[0m" if path != graphURI.path
      end
      if !graphURI.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d/) && timestamp = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value # find timestamp if graph not on timeline
        🕒 = [timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'),   # hour-dir
              %w{host path query}.map{|a|graphURI.send(a).yield_self{|p|p&&p.split(/[\W_]/)}}]. # graph name-slugs for timeline link
               flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.')[0..123] + '.ttl'
        unless File.exist? 🕒                                                                   # link 🐢 to timeline
          FileUtils.mkdir_p File.dirname 🕒
          FileUtils.ln f, 🕒 rescue nil
        end
      end}
    self
  end

  SummaryFields = [Abstract, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]

  # file (big) -> file (small)
  def summary
    return self if basename.match(/^(index|README)/) || !node.exist? # don't summarize README or index files or dangling symlinks

    summary_node = join(['.preview', basename, ['🐢','ttl'].member?(ext) ? nil : '🐢'].compact.join '.').R env
    file = summary_node.fsPath                                                 # summary file
    return summary_node if File.exist?(file) && File.mtime(file) >= node.mtime # summary up to date

    fullGraph = RDF::Repository.new # full graph
    miniGraph = RDF::Repository.new # summary graph
    loadRDF graph: fullGraph        # load full graph

    # summarize graph
    treeFromGraph(fullGraph).map{|subject, resource| # all subjects
      SummaryFields.map{|predicate|                  # summary predicates
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|       # summary objects
            miniGraph << RDF::Statement.new(subject.R,predicate.R,o)} # triple in summary-graph
        end} if [Image, Abstract, Title, Link, Video].find{|p|resource.has_key? p}}

    summary_node.writeFile miniGraph.dump(:turtle, base_uri: self, standard_prefixes: true) # store summary
    summary_node
  end

  # file (any MIME) -> file (turtle)
  def 🐢
    return self if ['🐢','ttl'].member? ext
    turtle_node = join(['', basename, '🐢'].join '.').R env
    file = turtle_node.fsPath                                                 # summary file
    return turtle_node if File.exist?(file) && File.mtime(file) >= node.mtime # summary up to date
    graph = RDF::Repository.new                                               # read RDF
    loadRDF graph: graph
    turtle_node.writeFile graph.dump(:turtle, base_uri: self, standard_prefixes: true) # store turtle
    turtle_node
  end

  # Repository -> JSON-compatible tree
  def treeFromGraph graph = nil
    graph ||= env[:repository]
    return {} unless graph

    tree = {}

    graph.each_triple{|s,p,o|
      s = s.to_s               # subject
      p = p.to_s               # predicate
      o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
      tree[s] ||= {'uri' => s} # insert subject
      tree[s][p] ||= []        # insert predicate
      if tree[s][p].class == Array
        tree[s][p].push o unless tree[s][p].member? o # insert in object-list
          else
            tree[s][p] = [tree[s][p],o] unless tree[s][p] == o # new object-list
      end}

    tree
  end
  include URIs
end
