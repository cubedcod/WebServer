class WebResource

  module URIs
    Instagram = 'www.instagram.com'
    YouTube = 'http://www.youtube.com/xml/schemas/2015#'
  end

  # TODO Dedupe video embeds within response representation
  module Webize

    def triplrImage &f
      yield uri, Type, Image.R
      yield uri, Image, self
      w,h = Dimensions.dimensions localPath
      yield uri, Schema+'width', w
      yield uri, Schema+'height', h
      triplrFile &f
    end

  end

  module HTTP

    UnwrapImage = -> re {
      img = ('https://'+re.host+re.path).R.nokogiri.css('[property="og:image"]').attr('content').to_s.R
      loc = img.host ? ('https://' + img.host + img.path) : img.path
      [302,{'Location' => loc},[]]}

  end

  module HTML

    Markup[Image] = -> image,env {
      if image.respond_to? :uri
        img = image.R
        if env[:images][img.uri]
        # deduplicated
        else
          env[:images][img.uri] = true # mark as shown
          {class: :thumb,
           c: {_: :a, href: img.uri,
               c: {_: :img, src: if !img.host # thumbnail
                    img.path + '?preview' if img.path
                  else
                    img.uri
                   end}}}
        end
      else
        CGI.escapeHTML image.to_s
      end
    }

    Markup[Video] = -> video,env {
      video = video.R
      if env[:images][video.uri]
      else
        env[:images][video.uri] = true
        if video.match /youtu/
          id = (HTTP.parseQs video.query)['v'] || video.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, gesture: "media", allow: "encrypted-media", allowfullscreen: :true}
        else
          {class: :video,
           c: [{_: :video, src: video.uri, controls: :true}, '<br>',
               {_: :span, class: :notes, c: video.basename}]}
        end
      end
    }

  end
end
