# coding: utf-8
class WebResource
  module HTML

    Treeize = -> graph {
      t = {}
      # visit nodes
      (graph.class==Array ? graph : graph.values).map{|node| re = node.R
        cursor = t  # cursor start
        # traverse
        [re.host ? re.host.split('.').reverse : nil, re.parts, re.qs, re.fragment].flatten.compact.map{|name|
          cursor = cursor[name] ||= {}}
        if cursor[:RDF] # merge to node
          node.map{|k,v|
            cursor[:RDF][k] = cursor[:RDF][k].justArray.concat v.justArray unless k == 'uri'}
        else
          cursor[:RDF] = node # insert node
        end}
      t } # tree

    SiteCSS = ConfDir.join('site.css').read
    SiteJS  = ConfDir.join('site.js').read

    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body
      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}
      # strip Javascript and tracking-images
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{quantserve scorecardresearch}.map{|co|
        html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # lift CSS background-image to image element
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).do{|url|
          node.add_child "<img src=\"#{url[1]}\">"}}

      # traverse nodes
      html.traverse{|e|
        # assign link identifier
        e.set_attribute 'id', 'id'+rand.to_s.sha2 if e['href'] && !e['id']
        # traverse attribute nodes
        e.attribute_nodes.map{|a|
          # load nonstandard @src attrs
          if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
            puts "updating @src #{e['src']} to #{a.value}" if e['src']
            e.set_attribute 'src', a.value
          end
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height layout ping role style tabindex target width}.member?(a.name)}}

      html.to_xhtml(:indent => 0)
    end

    def self.colorize bg = true
      "#{bg ? 'color' : 'background-color'}: black; #{bg ? 'background-' : ''}color: #{'#%06x' % (rand 16777216)}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph = {}

      # HEAD links
      @r ||= {}
      @r[:links] ||= {}
      @r[:images] ||= {}
      @r[:colors] ||= {}

      # title
      titleRes = [
        '#this', '',
        path && (path + '#this'), path,
        host && !path && ('//' + host + '#this'),
        host && !path && ('//' + host),
        host && path && ('https://' + host + path + '#this'),
        host && path && ('https://' + host + path),
        host && path && ('//' + host + path + '#this'),
        host && path && ('//' + host + path)
      ].compact.find{|u| graph[u] && !graph[u][Title].justArray.empty?}

      # render HEAD link as HTML
      link = -> key, displayname {
        @r[:links][key].do{|uri|
          [uri.R.data({id: key, label: displayname}),
           "\n"]}}


      htmlGrep graph, q['q'] if @r[:grep]
      subbed = subscribed?
      tabular = q['view'] == 'table'
      tabularOverview = '?view=table&sort=date'
      @r[:links][:up] = dirname + '/' + qs + '#r' + (path||'/').sha2 unless !path || path=='/'
      @r[:links][:down] = path + '/' if env['REQUEST_PATH'] && directory? && env['REQUEST_PATH'][-1] != '/'

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: ["\n\n",
                        {_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                            ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].justArray.map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             {_: :script, c: ["\n", SiteJS]}, "\n",
                             *@r[:links].do{|links|
                               links.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: ["\n", link[:up, '&#9650;'], {_: :a, id: :tabular, style: tabular ? 'color: #fff' : 'color: #555', href: tabular ? '?' : tabularOverview, c: '↨'},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             unless localNode?
                               {class: :toolbox,
                                c: {_: :a, id: :subscribe,
                                     href: '/' + (subbed ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + host + (@r['REQUEST_URI'] || path)}), class: subbed ? :on : :off, c: 'subscribe' + (subbed ? 'd' : '')}}
                             end,
                             if graph.empty?
                               HTML.keyval (HTML.webizeHash @r), @r # 404
                             elsif q['group']
                               p = q['group']
                               case p
                               when 'to'
                                 p = To
                               when 'from'
                                 p = Creator
                               end
                               bins = {}
                               graph.map{|uri, resource|
                                 resource[p].justArray.map{|o|
                                   o = o.to_s
                                   bins[o] ||= []
                                   bins[o].push resource}}
                               bins.map{|bin, resources|
                                 {class: :group, style: HTML.colorize, c: [{_: :span, class: :label, c: CGI.escapeHTML(bin)}, HTML.tabular(resources, @r)]}}
                             elsif tabular
                               HTML.tabular graph, @r       # table layout
                             else
                               env[:graph] = graph
                               HTML.tree Treeize[graph], @r # tree layout
                             end,
                             link[:down,'&#9660;']]}]}]
    end

    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || type.basename,
            c: [{_: :td, class: 'k', c: Markup[Type][type]},
                {_: :td, class: 'v', c: vs.justArray.map{|v|
                   value k, v, env}.intersperse(' ')}]}, "\n"] unless k=='uri' && vs.justArray[0].to_s.match?(/^_:/))}}
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

    Markup[Creator] = -> c, env, uris=nil {
      if c.respond_to? :uri
        u = c.R

        name = u.fragment ||
               u.basename.do{|b| ['','/'].member?(b) ? false : b} ||
               u.host.do{|h|h.sub(/\.com$/,'')} ||
               'user'

        color = env[:colors][name] ||= HTML.colorize
        {_: :a, id: 'a'+rand.to_s.sha2, class: :creator, style: color, href: uris.justArray[0] || c.uri, c: name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Post] = -> post , env {
      uri = post.uri.justArray[0]
      post.delete 'uri'
      post.delete Type
      titles = post.delete(Title).justArray.map(&:to_s).map(&:strip).uniq
      date = post.delete(Date).justArray[0]
      from = post.delete(From).justArray
      to = post.delete(To).justArray
      images = post.delete(Image).justArray
      content = post.delete(Content).justArray
      uri_hash = 'r' + uri.sha2
      {class: :post, id: uri_hash,
       c: [{_: :a, id: 'pt' + uri_hash, class: :id, c: '☚', href: uri},
           titles.map{|title|
             title = title.to_s.sub(/\/u\/\S+ on /,'')
             unless env[:title] == title
               env[:title] = title
               [{_: :a, id: 't'+rand.to_s.sha2, class: :title, href: uri, c: CGI.escapeHTML(title)}, ' ']
             end},
           ({_: :a, class: :date, id: 'date' + uri_hash, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/') + '#' + uri_hash, c: date} if date),
           images.map{|i| Markup[Image][i,env]},
           {_: :table, class: :fromTo,
            c: {_: :tr,
                c: [{_: :td, c: from.map{|f|Markup[Creator][f,env]}, class: :from},
                    {_: :td, c: '&rarr;'},
                    {_: :td, c: to.map{|f|Markup[Creator][f,env]}, class: :to}]}},
           content, ((HTML.keyval post, env) unless post.keys.size < 1)]}}

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
        if video.uri.match /youtu/
          id = (HTTP.parseQs video.query)['v'] || video.parts[-1]
          {_: :iframe, width: 560, height: 315, src: "https://www.youtube.com/embed/#{id}", frameborder: 0, gesture: "media", allow: "encrypted-media", allowfullscreen: :true}
        else
          {class: :video,
           c: [{_: :video, src: video.uri, controls: :true}, '<br>',
               {_: :span, class: :notes, c: video.basename}]}
        end
      end}

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
                c: x[:label][0] || (%w{gif ico jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML(x.uri[0..64]))})
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end

    def renderFeed graph
      HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                   {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                    c: [{_: :id, c: uri},
                        {_: :title, c: uri},
                        {_: :link, rel: :self, href: uri},
                        {_: :updated, c: Time.now.iso8601},
                        graph.map{|u,d|
                          {_: :entry,
                           c: [{_: :id, c: u}, {_: :link, href: u},
                               d[Date].do{|d|   {_: :updated, c: d[0]}},
                               d[Title].do{|t|  {_: :title,   c: t}},
                               d[Creator].do{|c|{_: :author,  c: c[0]}},
                               {_: :content, type: :xhtml,
                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                    c: d[Content]}}]}}]}]
    end

    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Content, DC+'hasFormat', Identifier, Image, Mtime, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if attr == 'date'
        graph = graph.sort_by{|r| r[attr].justArray[0].to_s}.reverse
      end
      titles = {}
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p|
              p = p.R
              slug = p.fragment || p.basename
              icon = Icons[p.uri] || slug
              {_: :td, class: 'k', c: env[:query]['sort'] == p.uri ? icon : {_: :a, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
           graph.map{|resource|
             [{_: :tr, c: keys.map{|k|
                 {_: :td, class: 'v',
                  c: if k=='uri' # title with URI subscript
                   ts = resource[Title].justArray
                   if ts.size > 0
                     ts.map{|t|
                       title = t.to_s.sub(/\/u\/\S+ on /,'')
                       if titles[title]
                         {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :id, c: '☚'}
                       else
                         titles[title] = true
                         {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :title,
                          c: [(CGI.escapeHTML title), ' ',
                              {_: :span, class: :uri, c: CGI.escapeHTML(resource.uri)}, ' ']}
                       end}
                   else
                     {_: :a, href: resource.uri, id: 'r' + rand.to_s.sha2, class: :id, c: '&#x1f517;'}
                   end
                 else
                   resource[k].justArray.map{|v|value k, v, env }
                  end}}},
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Image].justArray.map{|i|{style: 'max-width: 20em', c: Markup[Image][i,env]}},
                                resource[Content]]}} if (resource[Content] || resource[Image]) && !env[:query].has_key?('head'))]}]}
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
       c: [({_: (url ? :a : :span), class: :label, c: (CGI.escapeHTML name.to_s)}.update(url ? {href: url} : {}) if name),
           t.map{|_name, _t|
             if :RDF == _name
               value nil, _t, env
             else
               tree _t, env, _name
             end
           }]}.update(css ? css : {})
    end

    # tree with nested S -> P -> O indexing (renderer input)
    def treeFromGraph graph
      g = {}                    # empty tree

      # traverse
      graph.each_triple{|s,p,o| # (subject,predicate,object) triple
        s = s.to_s; p = p.to_s  # subject, predicate
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
        g[s] ||= {'uri'=>s}                      # insert subject
        g[s][p] ||= []                           # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object

      g # tree
    end

    # Markup dispatcher
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # supplied type argument
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
        # blank-node reference
        if v.uri.match?(/^_:/) && env[:graph] && env[:graph][v.uri]
          value nil, env[:graph][v.uri], env
        elsif %w{jpg JPG png PNG webp}.member? v.ext
          Markup[Image][v, env]
        else
          [v.data({label: CGI.escapeHTML((v.query || (v.basename && v.basename != '/' && v.basename) || (v.path && v.path != '/' && v.path) || v.host || v.to_s)[0..48])}), ' ']
        end
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end

    def self.webizeValue v, &y
      case v.class.to_s
      when 'Hash'
        webizeHash v, &y
      when 'String'
        webizeString v, &y
      when 'Array'
        v.map{|_v| webizeValue _v, &y }
      else
        v
      end
    end

    def self.webizeHash h, &y
      u = {}
      yield h if h['__typename'] || h['type']
      h.map{|k,v|
        u[k] = webizeValue v, &y}
      u
    end

    def self.webizeString str, &y
      if str.match? /^(http|\/)\S+$/
        str.R
      else
        str
      end
    end

  end
  include HTML
  module Webize
    include URIs
    BasicSlugs = %w{
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r reddit rss rssfeed
 sports source story
 t the threads topic tumblr
 uk utm www}
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
  # text -> HTML, also yielding found (rel,href) tuples to block
  def hrefs &blk               # leading/trailing <>()[] and trailing ,. not captured in URL
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
      (post.empty? && '' || post.hrefs(&blk)) # prob not properly tail-recursive, getting overflow on logfiles, may need to rework
  rescue
    puts "failed to scan #{self}"
    ''
  end
  def sha2; Digest::SHA2.hexdigest self end
  def to_utf8; encode('UTF-8', undef: :replace, invalid: :replace, replace: '?') end
end
