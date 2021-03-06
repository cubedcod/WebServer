# coding: utf-8
require 'org-ruby'
module Webize
  module Org
    class Format < RDF::Format
      content_type 'text/org',
                   aliases: %w(
                   text/x-org;q=0.8
                   ),
                   extensions: [:org]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @doc = input.respond_to?(:read) ? input.read : input
        @base = options[:base_uri].R
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
        source_tuples{|p,o|
          fn.call RDF::Statement.new(@base, p, o, :graph_name => @base)}
      end

      def source_tuples
        html = RDF::Literal Orgmode::Parser.new(@doc).to_html
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
class WebResource
  module HTML
    MarkupGroup['http://xmlns.com/foaf/0.1/Person'] = -> people, env {
      {_: :table, class: :people,
       c: {_: :tr,
           c: [{_: :td, c: :👥, style: 'font-size: 3em'},
               {_: :td, c: people.map{|person|
                  person.delete Type
                  HTML.keyval person, env
                }, style: 'background-color: black'}]}}
    }
  end
end
