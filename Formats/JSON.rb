require 'json'
module Webize
  module JSON

    def self.scan v, &y
      case v.class.to_s
      when 'Hash'
        yield v
        v.values.map{|_v| scan _v, &y }
      when 'Array'
        v.map{|_v| scan _v, &y }
      end
    end

    class Format < RDF::Format
      content_type 'application/json',
                   extensions: [:json, :webmanifest],
                   aliases: %w(
                    application/manifest+json;q=0.8
                    application/vnd.imgur.v1+json;q=0.1)
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].R
        @json = ::JSON.parse(input.respond_to?(:read) ? input.read : input) rescue (puts input.to_s.gsub(/\n/,' '); {})
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
        scanContent{|s, p, o, graph=nil|
          s = s.R
          graph ||= ['https://', s.host || 'localhost', s.path].join.R
          fn.call RDF::Statement.new(s, p.R,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype = RDF.XMLLiteral if p == Content
                                                                  l),
                                     graph_name: graph )}
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
                type = case attachment.extname
                       when /m4a|mp3|ogg|opus/i
                         Audio
                       when /mkv|mp4|webm/i
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
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, @json, &f
        else
          Webize::JSON.scan(@json){|h|
            if s = h['uri'] || h['url'] || h['link'] || h['canonical_url'] || h['src'] || ((h['id']||h['ID']||h['_id']) && ('#' + (h['id']||h['ID']||h['_id']).to_s))
              puts ::JSON.pretty_generate h if Verbose
              s = @base.join(s).R
              yield s, Type, Post.R if h.has_key? 'content'
              if s.parts[0] == 'users'
                host = ('https://' + s.host).R
                yield s, Creator, host.join(s.parts[0..1].join('/'))
                yield s, To, host
              end
              h.map{|p, v|
                unless %w(_id id uri).member? p
                  p = MetaMap[p] || p
                  puts [p, v].join "\t" unless p.to_s.match? /^(drop|http)/
                  (v.class == Array ? v : [v]).map{|o|
                    unless [Hash, NilClass].member?(o.class) || (o.class == String && o.empty?) # each non-nil terminal value
                      o = @base.join o if o.class == String && o.match?(/^(http|\/)\S+$/)       # resolve URI
                      case p
                      when Content
                        o = Webize::HTML.format o, @base if o.class == String                   # format HTML
                      when Link
                        p = Image if o.class==RDF::URI && %w(.jpg .png .webp).member?(o.R.extname) # image pointer
                      end
                      yield s, p, o
                    end} unless p == :drop
                end}
            end}
        end

      end
    end
  end
end
class WebResource

  # read RDF from JSON embedded in HTML
  def JSONembed doc, pattern, &b
    doc.css('script').map{|script|
      script.inner_text.lines.grep(pattern).map{|line|
        Webize::JSON::Reader.new(line.sub(/^[^{]+/,'').chomp.sub(/};.*/,'}'), base_uri: self).scanContent &b}}
  end
end
