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
        render({_: :a, href: x.uri, id: x[:id][0] || ('link'+rand.to_s.sha2), class: x[:class][0], c: x[:label][0] || (CGI.escapeHTML x.uri)})
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
    def self.colorizeBG k; colorize k end
    def self.colorizeFG k; colorize k, false end

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
                             ({_: :a, id: :originUI, href: '/ui/origin' + HTTP.qs({u: 'http:' + uri}), c: '⌘'} unless localNode?),
                             if graph.empty?
                               HTML.kv (HTML.urifyHash @r), @r
                             else
                               # Graph -> Tree -> Markup
                               treeize = Group[q['g']] || Group[path == '/' ? 'topdir' : 'tree']
                               Markup[Container][treeize[graph], @r]
                              end,
                             link[:down,'&#9660;']]}]}]
    end

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Type] = -> t,env=nil {
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
        {_: :a, id: 't'+rand.to_s.sha2, class: :title, href: uri, c: CGI.escapeHTML(title)}
      end}

    Markup[Creator] = -> c, env, uris=nil {
      if c.respond_to? :uri
        u = c.R

        name = u.fragment ||
               u.basename.do{|b| ['','/'].member?(b) ? false : b} ||
               u.host.do{|h|h.sub(/\.com$/,'')} ||
               'user'

        color = env[:colors][name] ||= (HTML.colorizeBG name)
        {_: :a, class: :creator, style: color, href: uris.justArray[0] || c.uri, c: name}
      else
        CGI.escapeHTML (c||'')
      end}

    Markup[Container] = -> container , env {
      container.delete Type
      uri = container.delete 'uri'
      name = container.delete :name
      title = container.delete Title
      color = '#%06x' % (rand 16777216)
      position = rand(100) / 100.0

      # child node(s) represented as Object, array of Object(s) or (URI-indexed) Hash
      contents = container.delete(Contains).do{|cs| cs.class == Hash ? cs.values : cs}.justArray

      multi = contents.size > 1
      styleC = multi ? "border: .08em solid #{color}; background: repeating-linear-gradient(#{rand(12)*30}deg, #000, #000 #{position}em, #{color} #{position}em, #{color} 1em)" : ''
      styleN = multi ? "background-color: #{color}" : ''

      {class: :container, style: styleC,
       c: [title ? Markup[Title][title.justArray[0], env, uri.justArray[0]] : ((name && multi) ? ("<span class=name style='#{styleN}'>" + (CGI.escapeHTML name) + "</span>") : ''),
           contents.map{|c| HTML.value(nil,c,env)}.intersperse(' '),
           # container metadata
           (HTML.kv(container, env) unless container.empty?)]}}

    # table {k => v} -> Markup
    def self.kv hash, env
      {_: :table,
       c: hash.map{|k,vs|
         type = k && k.R || '#untyped'.R
         [:name,'uri',Type].member?(k) ? '' : [{_: :tr, name: type.fragment || type.basename,
                                                c: ["\n ",
                                                    {_: :td, class: 'k', c: Markup[Type][type]},"\n ",
                                                    {_: :td, class: 'v', c: vs.justArray.map{|v| HTML.value k,v,env }.intersperse(' ')}]}, "\n"]}}
    end

    # tuple (k,v) -> Markup
    def self.value k, v, env
      if Abstract == k
        v # HTML content
      elsif Content == k
        v # HTML content
      elsif Markup[k] # predicate-type keyed
        Markup[k][v,env]
      elsif v.class == Hash # object-type keyed
        resource = v.R
        types = resource.types
        if (types.member? Post) || (types.member? BlogPost) || (types.member? Email)
          Markup[Post][v,env]
        elsif types.member? Container
          Markup[Container][v,env]
        else
          kv v, env
        end
      elsif k == 'uri'
        v.R # reference
      elsif v.class == WebResource
        v   # reference
      else # renderer undefined
        CGI.escapeHTML v.to_s
      end
    end

    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body

      # strip nodes
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s|
        html.css(s).remove}

      # visit attribute-nodes
      html.traverse{|e|
        e.attribute_nodes.map{|a|
          # move attributes
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name

          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height layout ping role style tabindex target width}.member?(a.name)}}

      # serialize
      html.to_xhtml(:indent => 0)
    end

    # parse HTML
    def nokogiri; Nokogiri::HTML.parse (open uri).read end

  end
  include HTML
  module Webize
    include URIs

    def indexHTML host
      # slip in link to exit document-supplied UI and return to user preference
      writeFile readFile.sub(/<body[^>]*>/, "<body><a id='localUI' href='/ui/local#{HTTP.qs({u: 'http://' + host + @r['REQUEST_URI']})}' style='position: fixed; top: 0; right: 0; z-index: 33; color: #000; background-color: #fff; font-size: 1.8em'>⌘</a>") if @r
      IndexHTML[host].do{|indexer| send indexer } || []
    end

    # HTML -> RDF
    def triplrHTML &f

      # parse HTML
      n = Nokogiri::HTML.parse readFile.to_utf8

      triplr = TriplrHTML[@r && @r['SERVER_NAME']]
      if triplr # host-mapped triplr
        send triplr, &f
      else
        yield uri, Content, HTML.clean(n.css('body').inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
      end

      n.css('title').map{|title| yield uri, Title, title.inner_text }

      # video
      ['video[src]', 'video > source[src]'].map{|vsel|
        n.css(vsel).map{|v|
          yield uri, Video, v.attr('src').R }}

      # doc-header metadata
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
              v = v.hrefs # substring URIs to <a href>
            else
              v = HTML.urifyString v # bare URI to resource-reference
            end

            yield uri, k, v unless k == :drop
          }}}

      # JSON-LD metadata

      graph = RDF::Graph.new
      # load doc-fragments to graph
      n.css('script[type="application/ld+json"]').map{|json|
        graph << ::JSON::LD::API.toRdf(::JSON.parse json)}
      # emit triples
      graph.each_triple{|s,p,o|
        yield s.to_s, p.to_s, [RDF::Node, RDF::URI].member?(o.class) ? o.R : o.value}

      triplrFile &f
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
