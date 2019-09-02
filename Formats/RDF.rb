# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # Repository -> turtle file(s)
  def index
    return unless env[:repository]
    updates = []
    env[:repository].each_graph.map{|graph|
      if n = graph.name # named graph
        n = n.R
        docs = []
        unless n.uri.match?(/^(_|data):/) # blank nodes and data-URIs not directly stored, only appearring in doc-context

          # canonical location
          if n.host # global graph
            docs.push (CacheDir + n.host + (n.path ? (n.path[-1]=='/' ? (n.path + 'index') : n.path) : '') + '.ttl').R
          else      # local graph
            docs.push (n.path + '.ttl').R unless n.exist?
          end

          # timeline location
          if timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value # timestamp query
            docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),       # hour-dir location
                       %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # tokenize slugs
                        flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist slugs
          end
        end

        docs.map{|doc|
          unless doc.exist?
            doc.dir.mkdir
            RDF::Writer.open(doc.relPath){|f|f << graph}
            updates << doc
          end}
      end}
    updates # indexed resources
  end

  def isRDF?; ext == 'ttl' end

  # WebResource -> Graph (RDF#load wrapper with format hints)
  def load options = {base_uri: (path.R env)}
    env[:repository] ||= RDF::Repository.new
    nodeStat unless isRDF?
    if file?
      if basename.index('msg.')==0 || path.index('/mail/sent/cur')==0
        # procmail doesnt allow suffix (like .eml), only prefix? email author if you find solution
        # presumably this is due to crazy maildir suffix-rewrites etc
        options[:format] = :mail
      elsif ext.match? /^html?$/
        options[:format] = :html
      elsif %w(Cookies).member? basename
        options[:format] = :sqlite
      elsif %w(changelog gophermap gophertag license makefile readme todo).member?(basename.downcase) || %w(cls gophermap old plist service socket sty textile xinetd watchr).member?(ext.downcase)
        options[:format] = :plaintext
      elsif %w(markdown).member? ext.downcase
        options[:format] = :markdown
      elsif %w(install-sh).member? basename.downcase
        options[:format] = :sourcecode
        options[:lang] = :sh
      elsif %w(gemfile rakefile).member?(basename.downcase) || %w(gemspec).member?(ext.downcase)
        options[:format] = :sourcecode
        options[:lang] = :ruby
      elsif %w(bash c cpp h hs pl py rb sh).member? ext.downcase
        options[:format] = :sourcecode
      end
      #puts [relPath, options[:format]].join ' '
      env[:repository].load relPath, options
    end
  rescue RDF::FormatError => e
    puts [e.class, e.message].join ' '
  end

  # Graph -> JSON-compatible URI-indexed Hash (Feed & HTML-renderer input)
  def treeFromGraph
    tree = {}
    head = env[:query].has_key? 'head'
    env[:repository].each_triple{|s,p,o|
      s = s.to_s # subject URI
      p = p.to_s # predicate URI
      unless p == 'http://www.w3.org/1999/xhtml/vocab#role' || (head && p == Content)
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        tree[s][p].push o unless tree[s][p].member? o # object
      end}
    env[:graph] = tree
  end

  module POSIX
    def nodeStat options = {}                                           # STAT(1)
      return if basename.index('msg.') == 0
      subject = (options[:base_uri] || path.sub(/\.ttl$/,'')).R         # reference abstract generic node
      graph = env[:repository]
      if node.directory?
        subject = subject.path[-1] == '/' ? subject : (subject + '/')   # enforce trailing slash on container
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Container').R)
        children.map{|child|
          graph << (RDF::Statement.new subject, (W3+'ns/ldp#contains').R,
                                       child.node.directory? ? (child + '/') : child.path.sub(/\.ttl$/,'').R)}
      else
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/posix/stat#File').R)
      end
      graph << (RDF::Statement.new subject, Title.R, basename)
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)
      mtime = node.stat.mtime
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#mtime').R, mtime.to_i)
      graph << (RDF::Statement.new subject, Date.R, mtime.iso8601)
    end
  end
end

module Webize

  module URIlist

    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'

      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R.path.sub(/.u$/,'').R
        @doc = input.respond_to?(:read) ? input.read : input
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        fn.call RDF::Statement.new(@base, Type.R, (Schema+'BreadcrumbList').R)
        @doc.lines.map(&:chomp).map{|line|
          fn.call RDF::Statement.new @base, ('https://schema.org/itemListElement').R, line.R unless line.empty?
        }
      end
    end
  end
end
