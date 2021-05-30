# coding: utf-8
require 'rouge'
module Webize
  module Code
    include WebResource::URIs

    def self.clean str, base
      if !ScriptHosts.member?(base.host) && !base.env.has_key?(:scripts) && str.match?(ScriptGunk) && !ENV.has_key?('JS')
        base.env[:filtered] = true
        lines = str.split /[\n;]+/
        if Verbose
          lines.grep(ScriptGunk).map{|l| print "✂️ \e[38;5;8m" + l.gsub(/[\n\r\s\t]+/,' ').gsub(ScriptGunk, "\e[38;5;48m\\0\e[38;5;8m") + "\e[0m "}
          print "\n"
        end
        lines.grep_v(ScriptGunk).join ";\n"
      else
        str
      end
    end

    class Format < RDF::Format
      content_type 'application/ruby',
                   aliases: %w(
                   application/javascript;q=0.2
                   application/x-javascript;q=0.2
                   application/x-sh;q=0.2
                   text/css;q=0.2
                   text/x-c;q=0.8
                   text/x-perl;q=0.8
                   text/x-ruby;q=0.8
                   text/x-script.ruby;q=0.8
                   text/x-shellscript;q=0.8
                   ),
                   extensions: [:bash, :c, :css, :cpp, :erb, :gemspec, :go, :h, :hs, :js, :mk, :nim, :nix, :patch, :pl, :pm, :proto, :py, :rb, :sh, :zsh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @path = options[:path]
        @doc = (input.respond_to?(:read) ? input.read : input).encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '

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
        yield Type.R, (Schema + 'Code').R
        yield Title.R, @base.basename

        if @path # fs-path argument given, use pygmentize
          #lang = 'html' if File.extname(@path) == 'erb'
          #langtag = "-l #{lang}" if lang
          html = `pygmentize #{langtag} -f html #{Shellwords.escape @path}`

        else # Rouge
          lexer = Rouge::Lexer.guess_by_filename(@base.basename)
          html = Rouge::Formatters::HTMLPygments.new(Rouge::Formatters::HTML.new).format(lexer.lex(@doc))
        end

        html = RDF::Literal [html,
                             '<style>', CodeCSS, '</style>'
                            ].join.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
