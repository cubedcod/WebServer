# coding: utf-8
class WebResource

  # Graph -> files
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

  module POSIX

    # filesystem metadata -> Graph
    def nodeStat options = {}                                           # STAT(1)
      return if basename.index('msg.') == 0
      subject = (options[:base_uri] || path.sub(/\.(md|ttl)$/,'')).R    # abstract node subject
      graph = env[:repository] ||= RDF::Repository.new
      if node.directory?
        subject = subject.path[-1] == '/' ? subject : (subject + '/')   # trailing slash on container URI
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/ldp#Container').R)
        node.children.map{|n|
          name = n.basename.to_s
          name = n.directory? ? (name + '/') : name.sub(/\.ttl$/, '')
          child = subject.join name                                               # child node
          graph << (RDF::Statement.new child, Title.R, name)
          if n.file?
            graph << (RDF::Statement.new child, (W3+'ns/posix/stat#size').R, n.size)
            graph << (RDF::Statement.new child, Date.R, n.stat.mtime.iso8601)
          end
          graph << (RDF::Statement.new subject, (W3+'ns/ldp#contains').R, child)} # containment triple
      else
        graph << (RDF::Statement.new subject, Type.R, (W3+'ns/posix/stat#File').R)
      end
      graph << (RDF::Statement.new subject, Title.R, basename)
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#size').R, node.size)
      mtime = node.stat.mtime
      graph << (RDF::Statement.new subject, (W3+'ns/posix/stat#mtime').R, mtime.to_i)
      graph << (RDF::Statement.new subject, Date.R, mtime.iso8601)
      self
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
