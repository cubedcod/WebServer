# coding: utf-8
class WebResource
  module HTML

    # Markup -> HTML
    def self.render x
      case x
      when String
        x
      when Hash # element
        void = [:img, :input, :link, :meta].member? x[:_]
        '<' + (x[:_] || 'div').to_s +                        # open
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # children
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close
      when Array
        x.map{|n|render n}.join
      when WebResource
        render({_: :a, href: x.uri, id: x[:id][0] || ('link'+rand.to_s.sha2), class: x[:class][0],
                c: x[:label][0] || (%w{gif ico jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML(x.uri))})
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end

    def self.colorize k, bg = true
      return '' if !k || k.empty? || k.match(/^[0-9]+$/)
      "#{bg ? 'color' : 'background-color'}: black; #{bg ? 'background-' : ''}color: #{'#%06x' % (rand 16777216)}"
    end

    def self.webizeValue v
      case v.class.to_s
      when 'Hash'
        HTML.webizeHash v
      when 'String'
        HTML.webizeString v
      when 'Array'
        v.map{|_v| HTML.webizeValue _v }
      else
        v
      end
    end

    def self.webizeHash h
      u = {}
      h.map{|k,v|
        u[k] = HTML.webizeValue v}
      u
    end

    def self.webizeString str
      if str.match? /^(http|\/)\S+$/
        if str.match? /\.(jpg|png|webp)/i
          {'uri' => str, Type => Image.R}
        elsif str.match? /afs-prod\/media/
          {'uri' => str + '3000.jpeg', Type => Image.R}
        else
          str.R
        end
      else
        str
      end
    end

    SiteCSS = ConfDir.join('site.css').read
    SiteJS  = ConfDir.join('site.js').read

    # Graph -> HTML
    def htmlDocument graph = {}

      # HEAD links
      @r ||= {}
      @r[:links] ||= {}
      @r[:images] ||= {}
      @r[:colors] ||= {}

      # title
      title = graph[(path||'')+'#this'].do{|r|
        r[Title].justArray[0]} || # title in RDF
              [*(path||'').split('/'), q['q'], q['f']].
                map{|e|
        e && URI.unescape(e)}.join(' ') # path-derived title

      # header (k,v) -> HTML
      link = -> key, displayname {
        @r[:links][key].do{|uri|
          [uri.R.data({id: key, label: displayname}),
           "\n"]}}

      # filtered graph -> HTML
      htmlGrep graph, q['q'] if @r[:grep]

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: ["\n\n",
                        {_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                             {_: :title, c: title},
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             {_: :script, c: ["\n", SiteJS]}, "\n",
                             *@r[:links].do{|links|
                               links.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: ["\n", link[:up, '&#9650;'], link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             unless localNode?
                               {class: :toolbox,
                                c: [if subscribable?
                                    s = subscribed?
                                    {_: :a, id: :subscribe,
                                     href: '/' + (s ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + host + @r['REQUEST_URI']}),
                                     class: s ? :on : :off, c: 'subscribe' + (s ? 'd' : '')}
                                    end]}
                             end,
                             if graph.empty?
                               HTML.keyval (HTML.webizeHash @r), @r # 404
                             elsif localNode? && directory? && env['REQUEST_PATH'][-1] != '/' # overview of content
                               HTML.tabular graph, @r
                             else
                               HTML.tree (Group[q['g']] || # custom layout
                                          Group['tree']    # graph -> tree
                                                       )[graph], @r
                             end,
                             link[:down,'&#9660;']]}]}]
    end

    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Type] = -> t, env=nil {
      if t.respond_to? :uri
        t = t.R
        {_: :a, href: t.uri,
         c: Icons[t.uri] || t.fragment || t.basename}
      else
        CGI.escapeHTML t.to_s
      end}

    Markup[Title] = -> raw, env, uri='' {
      title = raw.to_s.sub(/\/u\/\S+ on /,'')
      unless env[:title] == title
        env[:title] = title
        [{_: :a, id: 't'+rand.to_s.sha2, class: :title, href: uri, c: CGI.escapeHTML(title)}, ' ']
      end}

    Markup[Creator] = -> c, env, uris=nil {
      if c.respond_to? :uri
        u = c.R

        name = u.fragment ||
               u.basename.do{|b| ['','/'].member?(b) ? false : b} ||
               u.host.do{|h|h.sub(/\.com$/,'')} ||
               'user'

        color = env[:colors][name] ||= (HTML.colorize name)
        {_: :a, id: 'a'+rand.to_s.sha2, class: :creator, style: color, href: uris.justArray[0] || c.uri, c: name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Image] = -> image,env {
      if image.respond_to? :uri
        img = image.R
        if env[:images] && env[:images][img.uri]
        # deduplicate
        else
          env[:images] ||= {}
          env[:images][img.uri] = true
          {class: :thumb, c: {_: :a, href: img.uri, c: {_: :img, src: img.uri}}}
        end
      else
        CGI.escapeHTML image.to_s
      end}

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
      end}

    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         type = k && k.R || '#untyped'.R
         [:name,'uri',Type].member?(k) ? '' : [{_: :tr, name: type.fragment || type.basename,
                                                c: [{_: :td, class: 'k', c: Markup[Type][type]},
                                                    {_: :td, class: 'v', c: vs.justArray.map{|v|
                                                       value k, v, env}.intersperse(' ')}]}, "\n"]}}
    end

    def self.tabular graph, env
      keys = graph.map{|uri,resource| resource.keys}.flatten.uniq - [Content]
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p| {_: :td, c: Markup[Type][p.R]}}},
           graph.map{|uri,resource|
             [{_: :tr, c: keys.map{|k|
                {_: :td, c: resource[k].justArray.map{|v|
                   value k, v, env }}}},
              ({_: :tr, c: {_: :td, colspan: keys.size, c: resource[Content]}} if resource[Content])]}]}
    end

    def self.tree t, env, name=nil
      url = t[:RDF].uri if t[:RDF]
      if name && t.keys.size > 1
        color = '#%06x' % rand(16777216)
        scale = rand(7) + 1
        position = scale * rand(960) / 960.0
        css = {style: "border: .08em solid #{color}; background: repeating-linear-gradient(#{rand 360}deg, #000, #000 #{position}em, #{color} #{position}em, #{color} #{scale}em)"}
      end

      {class: :tree,
       c: [({_: (url ? :a : :span), class: :label, c: (CGI.escapeHTML name.to_s)}.update(url ? {href: url} : {}) if name), '<br>',
           t.map{|_name, _t|
             if :RDF == _name
               value nil, _t, env
             else
               tree _t, env, _name
             end
           }]}.update(css ? css : {})
    end

    # Markup dispatcher
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # type-arg precedence over RDF type
        Markup[type][v,env]
      elsif v.class == Hash # RDF type
        resource = v.R
        types = resource.types
        if (types.member? Post) || (types.member? BlogPost) || (types.member? Email)
          Markup[Post][v,env]
        elsif types.member? Image
          Markup[Image][v,env]
        else
          keyval v, env
        end
      elsif v.class == WebResource
        v
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end

    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body

      # strip nodes
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}

      # strip Javascript and trackers
      html.css('a[href^="javascript"]').map{|a| a.remove }
      html.css('img[src*="scorecardresearch"]').map{|img| img.remove }

      # move CSS background-image to src attribute
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).do{|url|
          node.add_child "<img src=\"#{url[1]}\">"}}

      html.traverse{|e|
        e.attribute_nodes.map{|a|
          # find nonstandard src attribute. assume canonical is placeholder if both exist
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name

          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor height layout ping role style tabindex target width}.member?(a.name)}}

      # serialize
      html.to_xhtml(:indent => 0)
    end

  end
  include HTML
  module URIs
    IndexHTML = {}
  end
  module Webize
    include URIs

    BasicGunk = %w{
        [class*='cookie']  [id*='cookie']
        [class*='feature'] [id*='feature']
        [class*='message'] [id*='message']
        [class*='related'] [id*='related']
        [class*='share']   [id*='share']
        [class*='social']  [id*='social']
        [class*='topbar']  [id*='topbar']
aside   [class*='aside']   [id*='aside']
footer  [class*='footer']  [id*='footer']
header  [class*='header']  [id*='header'] [class*='Header'] [id*='Header']
nav     [class*='nav']     [id*='nav']
sidebar [class^='side']    [id^='side']
}#.map{|sel| sel.sub /\]$/, ' i]'} #TODO see if Oga et al support case-insensitive attribute-selectors https://gitlab.com/yorickpeterse/oga

    # HTML -> RDF
    def triplrHTML &f
      n = Nokogiri::HTML.parse readFile.to_utf8 # parse

      # <body>
      if body = n.css('body')[0]
        # move site links to footer
        [*BasicGunk,*Gunk].map{|selector|
          body.css(selector).map{|sel|
            body.add_child sel.remove}}
        yield uri, Content, HTML.clean(body.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '') unless (@r && @r['SERVER_NAME'] || host || '').match? /twitter.com/
      end

      # <title>
      n.css('title').map{|title| yield uri, Title, title.inner_text }

      # <video>
      ['video[src]', 'video > source[src]'].map{|vsel|
        n.css(vsel).map{|v|
          yield uri, Video, v.attr('src').R }}

      # <link>
      n.css('head link[rel]').map{|m|
        m.attr("rel").do{|k| # predicate
          m.attr("href").do{|v| # object
            k = {
              'alternate' => DC + 'hasFormat',
              'icon' => Image,
              'image_src' => Image,
              'apple-touch-icon' => Image,
              'apple-touch-icon-precomposed' => Image,
              'shortcut icon' => Image,
              'stylesheet' => :drop,
            }[k] || k
            yield uri, k, v.R unless k == :drop
          }}}

      # <meta>
      n.css('head meta').map{|m|
        (m.attr("name") || m.attr("property")).do{|k| # predicate
          m.attr("content").do{|v| # object

            # normalize predicates
            k = {
              'article:modified_time' => Date,
              'article:published_time' => Date,
              'description' => Abstract,
              'image' => Image,
              'msapplication-TileImage' => Image,
              'og:description' => Abstract,
              'og:image' => Image,
              'og:image:height' => Schema + 'height',
              'og:image:secure_url' => Image,
              'og:image:width' => Schema + 'width',
              'og:title' => Title,
              'sailthru.date' => Date,
              'sailthru.description' => Abstract,
              'sailthru.image.thumb' => Image,
              'sailthru.image.full' => Image,
              'sailthru.lead_image' => Image,
              'sailthru.secondary_image' => Image,
              'sailthru.title' => Title,
              'thumbnail' => Image,
              'twitter:creator' => Creator,
              'twitter:description' => Abstract,
              'twitter:image' => Image,
              'twitter:image:src' => Image,
              'twitter:title' => Title,
              'viewport' => :drop,
            }[k] || k

            case k
            when 'twitter:site'
              k = Twitter
              v = (Twitter + '/' + v.sub(/^@/,'')).R
            when Abstract
              v = v.hrefs
            else
              v = HTML.webizeString v
            end

            yield uri, k, v unless k == :drop
          }}}

      # JSON-LD
      graph = RDF::Graph.new
      n.css('script[type="application/ld+json"]').map{|json|
       tree = begin
               ::JSON.parse json.inner_text
             rescue
               puts "JSON parse failed: #{json.inner_text}"
               {}
             end
       graph << ::JSON::LD::API.toRdf(tree) rescue puts("JSON-LD toRDF error #{uri}")}
      graph.each_triple{|s,p,o|
        yield s.to_s, p.to_s, [RDF::Node, RDF::URI].member?(o.class) ? o.R : o.value}

      # host-specific triplr
      if hostTriples = @r && Triplr[:HTML][@r['SERVER_NAME']]
        send hostTriples, n, &f
      end
    end

  end
  include Webize
end

module Redcarpet
  module Render
    class Pygment < HTML
      def block_code(code, lang)
        if lang
          IO.popen("pygmentize -l #{lang.downcase.sh} -f html",'r+'){|p|
            p.puts code
            p.close_write
            p.read
          }
        else
          code
        end
      end
    end
  end
end

class String
  # text -> HTML. yield (rel,href) tuples to block
  def hrefs &blk
    # leading & trailing [<>()] stripped, trailing [,.] dropped
    pre, link, post = self.partition(/(https?:\/\/(\([^)>\s]*\)|[,.]\S|[^\s),.”\'\"<>\]])+)/)
    pre.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + # pre-match
      (link.empty? && '' ||
       '<a class="link" href="' + link.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;') + '">' +
       (resource = link.R
        if blk
          type = case link
                 when /(gif|jpg|jpeg|(jpg|png):(large|small|thumb)|png|webp)$/i
                   WebResource::Image
                 when /(youtube.com|(mkv|mp4|webm)$)/i
                   WebResource::Video
                 else
                   WebResource::Link
                 end
          yield type, resource
        end
        CGI.escapeHTML(resource.uri.sub /^http:../,'')) +
       '</a>') +
      (post.empty? && '' || post.hrefs(&blk)) # recursion on tail
  rescue
    puts "failed to scan #{self}"
    ''
  end
end
