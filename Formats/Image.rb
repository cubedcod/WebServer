# coding: utf-8
%w(exif).map{|_| require _}
module Webize
  module GIF
    class Format < RDF::Format
      content_type 'image/gif', :extension => :gif
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R
        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil
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
      end
    end
  end
  module HTML

    # alternate names for src and srcset attributes

    SRCnotSRC = %w(
data-baseurl
data-delayed-url
data-hi-res-src
data-image
data-img-src
data-lazy-img
data-lazy-src
data-menuimg
data-native-src
data-original
data-raw-src
data-src
image-src
)

    SRCSET = %w{data-lazy-srcset data-srcset}

  end
  module JPEG
    class Format < RDF::Format
      content_type 'image/jpeg',
                   extensions: [:jpeg, :jpg, :JPG],
                   aliases: %w(
                   image/jpg;q=0.8
                   image/x-icon;q=0.2)
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
#        @img = Exif::Data.new(input.respond_to?(:read) ? input.read : input) rescue nil
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
        return # EXIF segfaulting, investigate.. or use perl exiftool?
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject,
                                     p.R,
                                     (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples
        yield Image, @subject
        [:ifd0, :ifd1, :exif, :gps].map{|fields|
          @img[fields].map{|k,v|
            if k == :date_time
              yield Date, Time.parse(v.sub(':','-').sub(':','-')).iso8601 rescue nil
            else
              yield ('http://www.w3.org/2003/12/exif/ns#' + k.to_s), v.to_s.encode('UTF-8', undef: :replace, invalid: :replace, replace: '?')
            end
          }} if @img
      end
      
    end
  end
  module PNG
    class Format < RDF::Format
      content_type 'image/png', :extensions => [:ico, :png]
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
         @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
  module WebP
    class Format < RDF::Format
      content_type 'image/webp', :extension => :webp
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#image').R 
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
        image_tuples{|p, o|
          fn.call RDF::Statement.new(@subject, p, (o.class == WebResource || o.class == RDF::URI) ? o : RDF::Literal(o),
                                     :graph_name => @subject)}
      end

      def image_tuples

      end

    end
  end
end
class WebResource
  module HTML

    # single-character representation of a URI
    Icons = {
      'ArticleGQL' => '📝',
      Abstract => '✍',
      Audio => '🔊',
      Content => '',
      Creator => '👤',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      DC + 'rights' => '⚖️',
      Date => '⌚', 'http://purl.org/dc/terms/created' => '⌚', 'http://purl.org/dc/terms/modified' => '⌚',
      Image => '🖼️',
      LDP + 'Container' => '📁',
      LDP + 'contains' => '📁',
      Link => '☛',
      Post => '📝',
      SIOC + 'BlogPost' => '📝',
      SIOC + 'MailMessage' => '✉️',
      SIOC + 'MicroblogPost' => '🐦',
      SIOC + 'attachment' => '✉',
      SIOC + 'reply_of' => '↩',
      SIOC + 'richContent' => '',
      Schema + 'height' => '↕',
      Schema + 'ImageObject' => '🖼️',
      Schema + 'width' => '↔',
      Schema + 'DiscussionForumPosting' => '📝',
      Schema + 'sameAs' => '=',
      Stat + 'File' => '📄',
      To => '☇',
      Type => '📕',
      Video => '🎞',
      W3 + '2000/01/rdf-schema#Resource' => '🌐',
    }

    Markup[Image] = -> image, env {
      if img = if image.class == WebResource
                 image
               elsif image.class == String && image.match?(/^([\/]|http)/)
                 image
               else
                 image['https://schema.org/url'] || image[Schema+'url'] || image[Link] || image['uri']
               end
        img = img[0] if img.class == Array
        src = env[:base].join(img).R env
        [{class: :thumb,
          c: {_: :a, href: src.href,
              c: {_: :img, src: src.href}}}, " \n"]
      end}

  end

  module HTTP

    def self.status_icon status
      {202 => '➕',
       204 => '✅',
       301 => '➡️',
       302 => '➡️',
       303 => '➡️',
       304 => '✅',
       401 => '🚫',
       403 => '🚫',
       404 => '❓',
       410 => '❌',
       500 => '🚩'}[status] || (status == 200 ? nil : status)
    end

  end
end
