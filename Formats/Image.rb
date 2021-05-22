# coding: utf-8
%w(exif).map{|_| require _}
module Webize
  module GIF
    class Format < RDF::Format
      content_type 'image/gif', :extension => :gif, aliases: %w(image/GIF;q=0.8)
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
data-ezsrc
data-gl-src
data-hi-res-src
data-image
data-img
data-img-url
data-img-src
data-lazy
data-lazy-img
data-lazy-src
data-menuimg
data-native-src
data-original
data-raw-src
data-src
data-url
image-src
)

    SRCSET = %w{
data-ezsrcset
data-gl-srcset
data-lazy-srcset
data-srcset
}

    SrcSetRegex = /\s*(\S+)\s+([^,]+),*/

    # resolve @srcset refs
    def self.srcset node, base
      srcset = node['srcset'].scan(SrcSetRegex).map{|url, size|[(base.join url), size].join ' '}.join(', ')
      if srcset.empty?
        puts "srcset failed to parse: " + node['srcset']
      else
        node['srcset'] = srcset
      end
    end

  end
  module JPEG
    class Format < RDF::Format
      content_type 'image/jpeg',
                   extensions: [:jpeg, :jpg, :JPG],
                   aliases: %w(
                   application/x-icon;q=0.2
                   image/avif;q=0.2
                   image/jpg;q=0.8
                   image/x-icon;q=0.2
                   image/vnd.microsoft.icon;q=0.2
)
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

    # URI -> emoji
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
      DOAP+'license' => '⚖️',
      Image => '🖼️',
      LDP + 'Container' => '📁',
      LDP + 'contains' => '📁',
      Link => '☛',
      Post => '📝',
      SIOC + 'BlogPost' => '📝',
      SIOC + 'MailMessage' => '✉️',
      SIOC + 'InstantMessage' => '🐦',
      SIOC + 'MicroblogPost' => '🐦',
      SIOC + 'attachment' => '✉',
      SIOC + 'reply_of' => '↩',
      SIOC + 'richContent' => '',
      Schema + 'height' => '↕',
      Schema + 'ImageObject' => '🖼️',
      Schema + 'width' => '↔',
      Schema + 'DiscussionForumPosting' => '📝',
      Schema + 'sameAs' => '=',
      Schema + 'SearchResult' => '🔎',
      Stat + 'File' => '📄',
      To => '☇',
      Type => '📕',
      Video => '🎞',
      W3 + '2000/01/rdf-schema#Resource' => '🌐',
    }

    Markup[Image] = Markup[Schema+'icon'] =  -> image, env {
      if img = if image.class == WebResource
                 image
               elsif image.class == String && image.match?(/^([\/]|http)/)
                 image
               else
                 image['https://schema.org/url'] || image[Schema+'url'] || image[Link] || image['uri']
               end
        img = img[0] if img.class == Array
        img = env[:base].join(img).R env
        src = img.href
        {_: :a, class: :thumb, id: 'i'+Digest::SHA2.hexdigest(rand.to_s), href: src,
         c: [{_: :img, src: src},
             {_: :span, c: (CGI.escapeHTML img.basename)}]}
      end}

  end

  module  URIs

    def format_icon mime=nil
      mime ||= ''
      x = path ? ext.downcase : ''
      if x == 'css' || mime.match?(/text\/css/)
        '🎨'
      elsif x == 'js' || mime.match?(/script/)
        '📜'
      elsif x == 'json' || mime.match?(/json/)
        '🗒'
      elsif %w(gif jpeg jpg png svg webp).member?(x) || mime.match?(/^image/)
        '🖼️'
      elsif %w(aac flac m4a mp3 ogg opus).member?(x) || mime.match?(/^audio/)
        '🔉'
      elsif %w(mkv mp4 ts webm).member?(x) || mime.match?(/^video/)
        '🎞️'
      elsif %w(m3u8).member? x
        '🎬'
      elsif x == 'txt' || mime.match?(/text\/plain/)
        '🇹'
      elsif x == 'ttl' || mime.match?(/text\/turtle/)
        '🐢'
      elsif %w(htm html).member?(x) || mime.match?(/html/)
        '📃'
      elsif mime.match? /atom|rss|xml/
        '📰'
      elsif mime.match? /^(application\/)?font/
        '🇦'
      elsif mime.match? /octet.stream/
        '🧱'
      else
        mime
      end
    end

  end

  module HTTP

    def self.action_icon action, fetched=true
      case action
      when 'HEAD'
        '🗣'
      when 'OPTIONS'
        '🔧'
      when 'POST'
        '📝'
      when 'GET'
        fetched ? '🐕' : ' '
      else
        action
      end
    end

    def self.format_color format_icon
      case format_icon
      when '➡️'
        '38;5;7'
      when '📃'
        '38;5;231'
      when '📜'
        '38;5;51'
      when '🗒'
        '38;5;165'
      when '🐢'
        '38;5;48'
      when '🎨'
        '38;5;227'
      when '🖼️'
        '38;5;226'
      when '🎬'
        '38;5;208'
      else
        '35;1'
      end
    end

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
       408 => '🔌',
       410 => '❌',
       500 => '🚩',
       503 => '🔌'}[status] || (status == 200 ? nil : status)
    end

  end
end
