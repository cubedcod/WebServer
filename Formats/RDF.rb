# coding: utf-8
class WebResource

  # file -> Repository: wrap RDF#load, adding type-hints and skipping full read of media-files
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    if node.file?
      if %w(info pack part svg ytdl).member? ext           # incomplete/tmpfiles, ignore
        puts "no RDF reader for file #{fsPath}"
      elsif %w(gif jpg png webp).member? ext               # image
        graph << RDF::Statement.new(self, Type.R, Image.R)
        graph << RDF::Statement.new(self, Title.R, basename)
      elsif %w(mp4 mkv webm).member? ext                   # video
        graph << RDF::Statement.new(self, Type.R, Video.R)
      elsif %w(m4a mp3 ogg opus wav).member? ext           # audio
        tag_triples graph
      else                                                 # read w/ RDF::Reader
        options = {}
        name = basename.downcase                           # case-normalized basename
        if ext.empty?                                      # suffix undefined
          if %w(changelog copying license readme todo).member? name
            options[:content_type] = 'text/plain'          # common textfile names
          elsif %w(gemfile makefile rakefile).member? name
            reader = RDF::Reader.for(:code)                # common buildfile names
          else
            puts "format-suffix undefined: #{self}"        # ask FILE(1) for MIME hint
            options[:content_type] = `file -b --mime-type #{Shellwords.escape fsPath}`.chomp
          end
        elsif name.index('msg.')==0 || path.index('/sent/cur')==0
          options[:content_type] = 'message/rfc822'        # mail prefix or maildir-contained
        else                                               # suffix -> MIME map
          options[:content_type] = Suffixes.invert[suffix] || Rack::Mime::MIME_TYPES[suffix] 
          options[:file_extension] = ext
        end

        if reader ||= RDF::Reader.for(**options)           # select reader
          reader.new(File.open(fsPath).read,base_uri: self){|_|graph << _} # read RDF
        else
          puts "no RDF reader for #{uri}"                  # no reader found
        end
      end
    elsif node.directory?
      dir_triples graph                                    # directory metadata
    end
    self
  end

  # Repository -> 🐢 file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]                                           # repository to store
    (repository || env[:repository]).each_graph.map{|graph|                                     # graph
      graphURI = (graph.name || self).R                                                         # graph URI
      fsBase = graphURI.fsPath                                                                  # storage path
      fsBase += '/index' if fsBase[-1] == '/'
      f = fsBase + '.🐢'

      unless File.exist? f
        FileUtils.mkdir_p File.dirname f
        RDF::Writer.for(:turtle).open(f){|f|f << graph}                                         # write 🐢
        puts "\e[38;5;48m#{'%2d' % graph.size}⋮🐢 \e[1m#{'http://localhost:8000' if !graphURI.host}#{graphURI}\e[0m" if path != graphURI.path
      end

      if !graphURI.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d/) && (ts = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value) && ts.match?(/^\d\d\d\d-/) # canonical location is not on timeline and graph has timestamp
        puts graph.query(RDF::Query::Pattern.new(:s, Creator.R, :o)).objects
        🕒 = [ts.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'),          # hour-dir
              %w{host path query}.map{|a|graphURI.send(a).yield_self{|p|p&&p.split(/[\W_]/)}}]. # name slugs
               flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.')[0..125] + '.🐢'   # timeline URI

        unless File.exist? 🕒                                                                   # link 🐢 to timeline
          FileUtils.mkdir_p File.dirname 🕒
          FileUtils.ln f, 🕒 rescue nil
          puts ['🕒', ts, 🕒].join ' '
        end
      end}
    self
  end

  # file -> 🐢 file (data-reduced preview)
  def preview
    return self if basename.match(/^(index|README)/) || !node.exist?           # don't summarize index or README
    summary_node = join(['.', basename, ['🐢','ttl'].member?(ext) ? nil : '🐢'].compact.join '.').R env # summary URI
    file = summary_node.fsPath                                                 # summary file
    return summary_node if File.exist?(file) && File.mtime(file) >= node.mtime # summary up to date
    fullGraph = RDF::Repository.new                                            # full RDF
    miniGraph = RDF::Repository.new                                            # summary RDF
    loadRDF graph: fullGraph                                                   # read RDF
    saveRDF fullGraph if basename.index('msg.') == 0                           # store RDF read from non-RDF
    treeFromGraph(fullGraph).map{|subject, resource|                           # summarizable resources
      tiny = (resource[Type]||[]).member? (SIOC + 'MicroblogPost').R           # retain full content if micropost
      predicates = [Abstract, Audio, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]
      predicates.push Content if tiny
      predicates.map{|predicate|                                               # summary predicate(s)
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|                                 # summary object(s)
            miniGraph << RDF::Statement.new(subject.R,predicate.R,o)} # triple to summary-graph
        end} if [Image, Abstract, Title, Link, Video].find{|p|resource.has_key? p} || tiny}
    summary_node.writeFile miniGraph.dump(:turtle, base_uri: self, standard_prefixes: true) # store summary RDF
    summary_node                                                                            # summary
  end

  include URIs

  module HTML

    Markup[Type] = -> t, env {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.display_name}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

  end
end

# 🐢 file-extension
RDF::Format.file_extensions[:🐢] = RDF::Format.file_extensions[:ttl]
