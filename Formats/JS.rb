require 'json'
module Webize

  module JSON
    class Format < RDF::Format
      content_type 'application/json',
                   :extension => :json,
                   aliases: %w(text/javascript;q=0.8)
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @subject = (options[:base_uri] || '#image').R 
        @json = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue {}
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
        scanContent{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype = RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      def JSONfeed
        @json['items'].map{|item|
          s = @base.join(item['url'] || item['id'])
          yield s, Type, Post.R
          item.map{|p, o|
            case p
            when 'attachments'
              o.map{|a|
                attachment = @base.join(a['url']).R
                type = case attachment.ext.downcase
                       when /m4a|mp3|ogg|opus/
                         Audio
                       when /mkv|mp4|webm/
                         Video
                       else
                         Link
                       end
                yield s, type, attachment}
              p = :drop
            when 'author'
              yield s, Creator, o['name']
              yield s, Creator, o['url'].R
              p = :drop
            when 'content_text'
              p = Content
              o = CGI.escapeHTML o
            when 'tags'
              o.map{|tag| yield s, Abstract, tag }
              p = :drop
            end
            p = MetaMap[p] || p
            puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/
            yield s, p, o unless [:drop,'id','url'].member? p}} if @json['items'] && @json['items'].respond_to?(:map)
      end

      def scanContent &f

        ## JSON triplrs

        # host binding
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, @json, &f
        end

        # JSON-Feed
        if @base.parts.map{|part| part.split '.'}.flatten.member? 'feed'
          @base.env[:transform] = true
          self.JSONfeed &f
        end

      end
    end
  end
end
