module Webize
  module MP4
    class Format < RDF::Format
      content_type 'video/mp4', :extension => :mp4
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#mp3').R 
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
  module WebM
    class Format < RDF::Format
      content_type 'video/webm', :extension => :webm
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#mp3').R 
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
end
class WebResource
  module HTML
    Markup[Video] = -> video, env {
      src = if video.class == WebResource
              video.to_s
            elsif video.class == String && video.match?(/^http/)
              video
            else
              video['https://schema.org/url'] || video[Schema+'contentURL'] || video[Schema+'url'] || video[Link] || video['uri']
            end
      if src.class == Array
        puts "multiple video-src found:", src if src.size > 1
        src = src[0]
      end
      src = src.to_s
      src = src + '/DASH_480' if src.match /v.redd.it/
      if env[:images][src]
       # deduplicate
      else
        env[:images][src] = true
        if src.match /youtu/
          id = (HTTP.parseQs src.R.query)['v'] || src.R.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, gesture: "media", allow: "encrypted-media", allowfullscreen: :true}
        else
          {class: :video,
           c: [{_: :video, src: src, controls: :true}, '<br>',
               {_: :a, href: src, c: src.R.basename}]}
        end
      end}
  end
end
