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
               video                                                                                                               # video URL
             else
               video['https://schema.org/url'] || video[Schema+'contentURL'] || video[Schema+'url'] || video[Link] || video['uri'] # video in RDF reference
             end

        if v.class == Array
          puts "multiple videos, using first:" + v.join(', ') if v.size > 1
          v = v[0]
        end

        if v.to_s.match? /v.redd.it/ # reddit
          v += '/DASHPlaylist.mpd'   # append playlist suffix for dash.js
          dash = true
        end

        v = v.R env
        if v.uri.match? /youtu/      # youtube
          env[:tubes] ||= {}
          q = v.query_values || {}
          id = q['v'] || v.parts[-1]
          t = q['start'] || q['t']
          unless env[:tubes].has_key?(id)
            env[:tubes][id] = id
            if id == env[:qs]['v']   # navigated to video
              [{_: :a, id: :mainVideo},
               {_: :iframe, class: :main_player, width: 640, height: 480, src: "https://www.youtube.com/embed/#{id}#{t ? '?start='+t : nil}",
                frameborder: 0, allow: 'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture', allowfullscreen: :true}]
            else
              player = 'embed' + Digest::SHA2.hexdigest(rand.to_s)
              [{class: :preembed, onclick: "inlineplayer(\"##{player}\",\"#{id}\"); this.remove()",
                c: [{_: :img, src: "https://i.ytimg.com/vi_webp/#{id}/sddefault.webp"},{class: :icon, c: '&#9654;'}]}, {id: player}]
            end
          end
        else                         # generic video reference
          [dash ? '<script src="https://cdn.dashjs.org/latest/dash.all.min.js"></script>' : nil,
           {class: :video,
            c: [{_: :video, src: v.uri, controls: :true}.update(dash ? {'data-dashjs-player' => 1} : {}), '<br>',
                {_: :a, href: v.uri, c: v.display_name}]}]
        end
      end}

  end
end
