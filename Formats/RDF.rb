# coding: utf-8
class WebResource

  def indexRDF
    return self unless env[:repository]

    env[:repository].each_graph.map{|graph|
      n = graph.name.R # named-graph resource

      docs = []        # storage references

      unless n.uri.match?(/^(_|data):/) # blank node or data-URI only stored in context

        # canonical document location
        docs.push n.host ? (n.hostpath + (n.path ? (n.path[-1]=='/' ? (n.path + 'index') : n.path) : '')).R : n

        # temporal index location
        if timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value       # find timestamp
          docs.push ['/' + timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # build hour-dir path
                     %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p && p.split(/[\W_]/)}}]. # tokenize slugs
                      flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                     # apply slug skiplist
        end
      end

      docs.map{|doc|
        loc = doc.relPath + '.ttl'
        unless File.exist? loc
          doc.dir.mkdir
          RDF::Writer.for(:turtle).open(loc){|f|f << graph}
          print "\n🐢 \e[32;1m" + doc.uri + "\e[0m "
        end
      }
    }
    self
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
