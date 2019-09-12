# coding: utf-8
class WebResource

  # Repository -> turtle file(s)
  def index
    return unless env[:repository]
    env[:repository].each_graph.map{|graph|

      # calculate storage location
      if n = graph.name
        n = n.R   # graph pointer
        docs = [] # storage pointers

        unless n.uri.match?(/^(_|data):/) # blank nodes & data-URIs appear in a doc-context rather than directly stored

          # canonical location
          if n.host # global graph
            docs.push (n.hostpath + (n.path ? (n.path[-1]=='/' ? (n.path + 'index') : n.path) : '') + '.ttl').R
          else # local graph
            docs.push (n.path + '.ttl').R unless n.exist?
          end

          # timeline location
          if timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value           # timestamp query
            docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),       # hour-dir location
                       %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # tokenize slugs
                        flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist slugs
          end
        end

        # store RDF
        docs.map{|doc|
          unless doc.exist?
            doc.dir.mkdir
            RDF::Writer.open(doc.relPath){|f|f << graph}; puts ServerAddr + doc.path.sub(/\.ttl$/,'')
          end}
      end}
    self
  end

  # Graph -> JSON-compatible URI-indexed Hash (Feed & HTML-renderer input)
  def treeFromGraph
    tree = {}
    head = env && env[:query] && env[:query].has_key?('head')
    env[:repository].each_triple{|s,p,o|
      s = s.to_s # subject URI
      p = p.to_s # predicate URI
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

    def remoteDirStat
      return unless env[:repository].empty? && env['REQUEST_PATH'][-1]=='/' # unlistable remote?
      index = (hostpath + path).R(env)   # local list
      index.children.map{|e|e.env(env).nodeStat base_uri: (env[:scheme] || 'https') + '://' + e.relPath} if index.node.directory?
    end

    def nodeStat options = {}                                           # STAT(1)
      return if basename.index('msg.') == 0
      subject = (options[:base_uri] || path.sub(/\.(md|ttl)$/,'')).R    # abstract/generic-node reference
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
