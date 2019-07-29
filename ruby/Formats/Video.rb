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
    Markup[Video] = -> video,env {
      video = video.R
      if env[:images] && env[:images][video.uri]
      # deduplicated
      else
        env[:images] ||= {}
        env[:images][video.uri] = true
        if video.uri.match /youtu/
          id = (HTTP.parseQs video.query)['v'] || video.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, gesture: "media", allow: "encrypted-media", allowfullscreen: :true}
        else
          src = if video.uri.match /v.redd.it/
                  video.uri + '/DASH_480'
                else
                  video.uri
                end
          {class: :video,
           c: [{_: :video, src: src, controls: :true}, '<br>',
               {_: :span, class: :notes, c: video.basename}]}
        end
      end}
  end
end
