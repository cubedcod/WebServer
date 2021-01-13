module Webize
  module Code
    include WebResource::URIs

    def self.clean str, base
      if AllowJS.member? base.host
        str
      elsif gunk = (str.match ScriptGunk)
        base.env[:deny] = true
        ["// #{str.bytesize} bytes",
         "// gunk: #{gunk}"].join "\n"
      else
        str
      end
    end

    class Format < RDF::Format
      content_type 'application/ruby',
                   aliases: %w(
                   text/x-c;q=0.8
                   text/x-perl;q=0.8
                   text/x-ruby;q=0.8
                   text/x-shellscript;q=0.8
                   ),
                   extensions: [:bash, :c, :css, :cpp, :erb, :gemspec, :go, :h, :hs, :js, :mk, :nix, :patch, :pl, :pm, :proto, :py, :rb, :sh, :zsh]
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R

        extension = @base.ext
        @lang = 'html' if extension == 'erb'
        @lang = 'ruby' if options[:content_type] == 'text/x-ruby'
        @lang = 'shell' if options[:content_type] == 'text/x-shellscript'

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
        lang = "-l #{@lang}" if @lang
        html = RDF::Literal [`pygmentize #{lang} -f html #{@base.shellPath}`,
                             '<style>', CodeCSS, '</style>'
                            ].join.encode 'UTF-8', undef: :replace, invalid: :replace, replace: ' '
        html.datatype = RDF.XMLLiteral
        yield Content.R, html
      end
    end
  end
end
