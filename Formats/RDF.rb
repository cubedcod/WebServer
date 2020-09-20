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
        tag_triples graph
      else # read using RDF::Reader
        options = {base_uri: self} # reader options
        # format hints in name prefix/basename/location
        if format = if ext != 'ttl' && (basename.index('msg.') == 0 || path.index('/sent/cur') == 0) # email files w/ procmail PREFIX or sent-folder location
                   :mail
                 elsif ext.match? /^html?$/
                   :html
                 elsif %w(changelog license readme todo).member? basename.downcase
                   :plaintext
                 elsif %w(gemfile makefile rakefile).member? basename.downcase
                   :sourcecode
                    end
          options[:format] = format
        else # no format hints found
          if ext.empty? # no extension. ask FILE(1)
            mime = `file -b --mime-type #{shellPath}`.chomp
            options[:format] = :plaintext if mime == 'text/plain'
            options[:content_type] = mime # format from FILE(1)
          elsif mime = named_format
            options[:content_type] = mime # format from extension
          end
        end
        loc = fsPath
        if loc.index '#' # path contains chars disallowed in path portion of URI
          if reader = RDF::Reader.for(**options) # initialize reader
#            puts "READ #{fsPath}"
            reader.new(File.open(loc).read, base_uri: self){|_|graph << _} # read RDF
          end
        else
#          puts "LOAD #{fsPath}"
          graph.load 'file:' + loc, **options # load file: URI
        end
      end
    elsif node.directory?                     # directory
      dir_triples graph
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
      fsBase = graphURI.fsPath                                                                  # storage location
      fsBase += '/index' if fsBase[-1] == '/'
      🐢 = fsBase + '.ttl'
      unless File.exist? 🐢
        FileUtils.mkdir_p File.dirname 🐢
        RDF::Writer.for(:turtle).open(🐢){|f|f << graph}                                        # write 🐢
        puts "\e[32m#{'%2d' % graph.size}⋮🐢 \e[1m#{'http://localhost:8000' if !graphURI.host}#{graphURI}\e[0m" if path != graphURI.path
      end
      if !graphURI.to_s.match?(/^\/\d\d\d\d\/\d\d\/\d\d/) && timestamp = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value # find timestamp if graph not on timeline
        🕒 = [timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'),   # hour-dir
              %w{host path query}.map{|a|graphURI.send(a).yield_self{|p|p&&p.split(/[\W_]/)}}]. # graph name-slugs for timeline link
               flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.')[0..123] + '.ttl'
        unless File.exist? 🕒                                                                   # link 🐢 to timeline
          FileUtils.mkdir_p File.dirname 🕒
          FileUtils.ln 🐢, 🕒 rescue nil
        end
      end}
    self
  end

  SummaryFields = [Abstract, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]

  # node (big) -> node (small)
  def summary
    return self if basename.match(/^(index|README)/) || !node.exist? || node.size < 2048 # don't summarize README or index files or small nodes

    summary_node = join(['.preview', basename, ext == 'ttl' ? nil : 'ttl'].compact.join '.').R env
    🐢 = summary_node.fsPath                                               # summary file
    return summary_node if File.exist?(🐢) && File.mtime(🐢) >= node.mtime # summary up to date

    fullGraph = RDF::Repository.new # full graph
    miniGraph = RDF::Repository.new # summary graph
    loadRDF graph: fullGraph        # load full graph

    # summarize graph
    treeFromGraph(fullGraph).map{|subject, resource| # all subjects
      SummaryFields.map{|predicate|                  # summary predicates
        if o = resource[predicate]
          (o.class == Array ? o : [o]).map{|o|       # summary objects
            miniGraph << RDF::Statement.new(subject.R,predicate.R,o)} # triple in summary-graph
        end} if [Image, Abstract, Title, Link].find{|p|resource.has_key? p}}

    summary_node.writeFile miniGraph.dump(:turtle, standard_prefixes: true) # store summary
    summary_node
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
              {class: :body, c: links.group_by{|l|links.size > 25 ? ((l.host||'localhost').split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
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
