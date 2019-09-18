# coding: utf-8
class WebResource

  # Repository -> turtle files
  def index
    return self unless env[:repository]

    env[:repository].each_graph.map{|graph|
      n = graph.name.R # graph pointer
      docs = []

      unless n.uri.match?(/^(_|data):/) # unless blank node or data-URI

        # canonical document
        docs.push n.host ? (n.hostpath + (n.path ? (n.path[-1]=='/' ? (n.path + 'index') : n.path) : '')).R : n
        # time index
        if timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value     # timestamp query
          docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''), # hour-dir location
                     %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}}]. # URI slugs
                      flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                   # slugskip
        end
      end
      docs.map{|doc|
        unless doc.exist?
          doc.dir.mkdir
          RDF::Writer.for(:turtle).open(doc.relPath + '.ttl'){|f|
            f << graph}
        end}}
    self
  end

  def load options = {base_uri: (path.R env)}
    env[:repository] ||= RDF::Repository.new
    nodeStat unless isRDF?
    if node.file?
      if basename.index('msg.')==0 || path.index('/sent/cur')==0
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
      doc = self
      env[:repository].load doc.relPath, options
      end
  rescue RDF::FormatError => e
    puts [e.class, e.message].join ' '
  end

  # Graph -> JSON tree
  def treeFromGraph
    tree = {}
    head = env && env[:query] && env[:query].has_key?('head')
    env[:repository].each_triple{|s,p,o| s = s.to_s;  p = p.to_s
      unless p == 'http://www.w3.org/1999/xhtml/vocab#role' || (head && p == Content)
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        if tree[s][p].class == Array
          tree[s][p].push o unless tree[s][p].member? o # object
        else
          tree[s][p] = [tree[s][p],o] unless tree[s][p] == o
        end
      end}
    env[:graph] = tree
  end

  module POSIX

    def nodeStat options = {}                                           # STAT(1)
      return if basename.index('msg.') == 0
      subject = (options[:base_uri] || path.sub(/\.(md|ttl)$/,'')).R    # abstract-node reference
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
