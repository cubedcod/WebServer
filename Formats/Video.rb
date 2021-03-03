module Webize
  module MOV
    class Format < RDF::Format
      content_type 'video/quicktime', :extensions => [:mov,:MOV]
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

    MarkupGroup[Video] = -> files, env {
      [{_: :video, style: 'width: 100%', controls: :true, id: :video},
       tabular(files, env)]}

    Markup[Video] = Markup['WEB_PAGE_TYPE_WATCH'] = -> video, env {
      if v = if video.class == WebResource || (video.class == String && video.match?(/^http/))
               video
             else
               video['https://schema.org/url'] || video[Schema+'contentURL'] || video[Schema+'url'] || video[Link] || video['uri']
             end
        v = v[0] if v.class == Array
        if v.to_s.match? /v.redd.it/
          v += '/DASHPlaylist.mpd'
          dash = true
        end
        v = v.R env
        if v.uri.match? /youtu/
          q = v.query_values || {}
          id = q['v'] || v.parts[-1]
          if id == (env[:base].query_values||{})['v']
            t = q['start'] || q['t']
            {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}#{t ? '?start='+t : nil}", frameborder: 0, allow: 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture', allowfullscreen: :true}
          else
            {_: :a, href: v.uri, c: {_: :img, src: "https://i.ytimg.com/vi_webp/#{id}/sddefault.webp"}}
          end
        else
          [dash ? '<script src="https://cdn.dashjs.org/latest/dash.all.min.js"></script>' : nil,
           {class: :video,
            c: [{_: :video, src: v.uri, controls: :true}.update(dash ? {'data-dashjs-player' => 1} : {}), '<br>',
                {_: :a, href: v.uri, c: v.display_name}]}]
        end
      end}

  end
end
