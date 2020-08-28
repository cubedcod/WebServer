# coding: utf-8
require 'taglib'
class WebResource

  # local node -> RDF::Repository
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    if node.file?
      stat = node.stat
      unless ext == 'ttl'                                  # file-metadata triples
        graph << RDF::Statement.new(self, Title.R, Rack::Utils.unescape_path(basename))
        graph << RDF::Statement.new(self, Date.R, stat.mtime.iso8601)
        graph << RDF::Statement.new(self, (Stat + 'size').R, stat.size)
      end
      if %w(mp4 mkv webm).member? ext
        graph << RDF::Statement.new(self, Type.R, Video.R) # video-metadata triples
      elsif %w(m4a mp3 ogg opus wav).member? ext
        graph << RDF::Statement.new(self, Type.R, Audio.R) # audio-metadata triples via taglib
        TagLib::FileRef.open(fsPath) do |fileref|
          unless fileref.null?
            tag = fileref.tag
            graph << RDF::Statement.new(self, Title.R, tag.title)
            graph << RDF::Statement.new(self, Creator.R, tag.artist)
            graph << RDF::Statement.new(self, Date.R, tag.year) unless !tag.year || tag.year == 0
            graph << RDF::Statement.new(self, Content.R, tag.comment)
            graph << RDF::Statement.new(self, (Schema+'album').R, tag.album)
            graph << RDF::Statement.new(self, (Schema+'track').R, tag.track)
            graph << RDF::Statement.new(self, (Schema+'genre').R, tag.genre)
            graph << RDF::Statement.new(self, (Schema+'length').R, fileref.audio_properties.length_in_seconds)
          end
        end
      else
        # Reader has an extension-mapping, but sometimes we use hints from elsewhere, prefix, basename, even location (maildir cur/new/tmp)
        reader = if ext != 'ttl' && (basename.index('msg.') == 0 || path.index('/sent/cur') == 0) # email files
                   :mail # procmail doesnt have configurable SUFFIX (.eml), only PREFIX? - presumably due to maildir suffix-rewrites to denote state?
                 elsif ext.match? /^html?$/
                   :html # use our reader class, otherwise it tends to select RDFa
                 elsif %w(changelog license readme todo).member? basename.downcase
                   :plaintext
                 elsif %w(gemfile makefile rakefile).member? basename.downcase
                   :sourcecode
                 end
        # still no reader and no file-extension. ask FILE(1) for clue
        if !reader && ext.empty?
          mime = `file -b --mime-type #{shellPath}`.chomp
          reader = :plaintext if mime == 'text/plain'
        end

        # configure reader with hints gleaned above
        options = {base_uri: self}             # base URI for relative resolution
        options[:format] = reader if reader    # format hint from filename
        options[:content_type] = mime if mime  # MIME type from FILE(1)

        graph.load 'file:' + fsPath, **options # load RDF from file
      end
    elsif node.directory?                      # directory-entry triples
      subject = self                           # directory URI
      subject += '/' unless subject.to_s[-1] == '/' # enforce trailing-slash on dir-name
      graph << RDF::Statement.new(subject, Type.R, (LDP + 'Container').R)
      graph << RDF::Statement.new(subject, Title.R, basename)
      graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
      node.children.map{|child|                # point to child nodes
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename('.ttl').to_s.gsub(' ','%20').gsub('#','%23')))}
    end
    self
  rescue RDF::FormatError => e
    puts e.message,"RDF::FormatError :: #{mime} :: #{fsPath}"
    self
  end

  # RDF::Repository -> file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]
    (repository || env[:repository]).each_graph.map{|graph|
      graphURI = (graph.name || self).R
      turtle = graphURI.turtleFile                                                               # storage location
      unless File.exist? turtle
        FileUtils.mkdir_p File.dirname turtle
        RDF::Writer.for(:turtle).open(turtle){|f|f << graph}                                     # write Turtle
        puts "\e[32m#{'%2d' % graph.size}⋮🐢 \e[1m#{graphURI}\e[0m" if path != graphURI.path
      end
      if !graphURI.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d/) && timestamp = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value # find timestamp if graph not on timeline
        tlink = [timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # hour-dir
                %w{host path query}.map{|a|graphURI.send(a).yield_self{|p|p&&p.split(/[\W_]/)}}].# graph name-slugs for timeline link
                  flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.')[0..123] + '.ttl'
        unless File.exist? tlink                                                                 # link node to timeline
          FileUtils.mkdir_p File.dirname tlink
          FileUtils.ln turtle, tlink rescue nil
        end
      end}
    self
  end

  # file (big) -> Turtle file (small)
  def summary
    return self if basename.match(/^(index|README)/) || !node.exist? # don't summarize index or README file
    s = ('/summary/' + fsPath).R.turtleFile          # summary file
    unless File.exist?(s) && File.mtime(s) >= node.mtime # summary up to date
      fullGraph = RDF::Repository.new; miniGraph = RDF::Repository.new # graph storage 
      loadRDF graph: fullGraph                       # read RDF
      treeFromGraph(fullGraph).values.map{|resource| # bind subject
        subject = (resource['uri'] || '').R
        ps = [Abstract, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]
        type = resource[Type]
        type = [type] unless type.class == Array
        ps.push Content if type.member? (SIOC + 'MicroblogPost').R
        ps.map{|p|                                   # bind predicate
          if o = resource[p] ; p = p.R
            (o.class == Array ? o : [o]).map{|o|     # bind object
              miniGraph << RDF::Statement.new(subject,p,o)} # triple -> summary-graph
          end}}
      FileUtils.mkdir_p File.dirname s               # allocate fs-container
      RDF::Writer.for(:turtle).open(s){|f|f << miniGraph} # write summary
    end
    ('/' + s).R env
  end

  # graph -> tree (s -> p -> o) structure used by HTML + Feed serializers
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

  def turtleFile
    base  = fsPath
    base += '/index' if base[-1] == '/'
    base +  '.ttl'
  end

  include URIs

  module HTTP

    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
      format = selectFormat
      env[:resp]['Access-Control-Allow-Origin'] ||= allowed_origin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument
        when /^application\/atom+xml/
          feedDocument
        else
          env[:repository].dump RDF::Writer.for(content_type: format).to_sym, base_uri: self
        end}
    end

  end
  module HTML

    # RDF -> Markup
    def self.markup type, v, env
      if [Abstract, Content, 'http://rdfs.org/sioc/ns#richContent'].member? type
        v
      elsif Markup[type] # markup lambda defined for type-argument
        Markup[type][v,env]
      elsif v.class == Hash # data
        types = (v[Type] || []).map{|t|
          MarkupMap[t.to_s] || t.to_s } # normalize types for renderer application
        seen = false
        [types.map{|type|
          if f = Markup[type] # markup lambda defined for type
            seen = true
            f[v,env]
          end},
         (keyval v, env unless seen)] # default key-value renderer
      elsif v.class == WebResource # resource-reference
        v
      else # renderer undefined
        CGI.escapeHTML v.to_s
      end
    end

    Markup[DC+'language'] = -> lang, env {
      {'de' => '🇩🇪',
       'en' => '🇬🇧',
       'fr' => '🇫🇷',
       'ja' => '🇯🇵',
      }[lang] || lang}

    MarkupGroup[Link] = -> links, env {
      links.map(&:R).group_by{|l|links.size > 8 && l.host && l.host.split('.')[-1] || nil}.map{|tld, links|
        [{class: :container,
          c: [({class: :head, _: :span, c: tld} if tld),
              {class: :body, c: links.group_by{|l|links.size > 25 ? (l.host.split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
                 ['<table><tr>',
                  ({_: :td, class: :head, c: alpha} if alpha),
                  {_: :td, class: :body,
                   c: {_: :table, class: :links,
                       c: links.group_by(&:host).map{|host, paths|
                         {_: :tr,
                          c: [{_: :td, class: :host,
                               c: host ? (name = ('//' + host).R.display_name
                                          color = env[:colors][name] ||= '#%06x' % (rand 16777216)
                                          {_: :a, href: '/' + host, c: host, style: "background-color: #{color}; color: black"}) : []},
                              {_: :td, c: paths.map{|path| Markup[Link][path,env]}}]}}}},
                  '</tr></table>']}}]}, '&nbsp;']}}

    Markup[Link] = -> ref, env {
      u = ref.to_s
      re = u.R env
      [{_: :a, href: re.href, class: :path, c: (re.path||'/')[0..79], title: u, id: 'link' + Digest::SHA2.hexdigest(rand.to_s)},
       " \n"]}

    Markup[Type] = -> t, env {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || (t.path && t.basename)}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

  end

end
