# coding: utf-8
require 'nokogiri'
module Webize
  module HTML
    def self.clean body
      # parse
      html = Nokogiri::HTML.fragment body

      # strip elements
      %w{iframe link[rel='stylesheet'] style link[type='text/javascript'] link[as='script'] script}.map{|s| html.css(s).remove}

      # strip Javascript and tracker-images
      html.css('a[href^="javascript"]').map{|a| a.remove }
      %w{quantserve scorecardresearch}.map{|co|
        html.css('img[src*="' + co + '"]').map{|img| img.remove }}

      # CSS:background-image → <img>
      html.css('[style^="background-image"]').map{|node|
        node['style'].match(/url\('([^']+)'/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      # <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}

      # traverse nodes
      html.traverse{|e|
        e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) if e['href'] && !e['id'] # link identifier
        e.attribute_nodes.map{|a|
          # move nonstandard src attrs
          e.set_attribute 'src', a.value if %w{data-baseurl data-hi-res-src data-img-src data-lazy-img data-lazy-src data-menuimg data-native-src data-original data-src data-src1}.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name
          # strip attributes
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) || %w{bgcolor class height http-equiv layout ping role style tabindex target width}.member?(a.name)}}

      # unparse
      html.to_xhtml(:indent => 0)
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
      if block_given?
        yield h if h['__typename'] || h['type']
      end
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

    class Format < RDF::Format
      content_type     'text/html', :extension => :html
      content_encoding 'utf-8'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      BasicGunk = %w{
        [class*='cookie']  [id*='cookie']
        [class*='related'] [id*='related']
        [class*='share']   [id*='share']
        [class*='social']  [id*='social']
        [class*='topbar']  [id*='topbar']
        [class^='promo']   [id^='promo']  [class^='Promo']  [id^='Promo']
footer  [class^='footer']  [id^='footer']
header  [class*='header']  [id*='header'] [class*='Header'] [id*='Header']
nav     [class^='nav']     [id^='nav']
sidebar [class^='side']    [id^='side']
}

      def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input.read : input).encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ')
        @base = options[:base_uri].R

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
        scanContent{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal o
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      # HTML -> RDF
      def scanContent &f
        embeds = RDF::Graph.new # embedded graph-data
        subject = @base         # subject URI
        n = Nokogiri::HTML.parse @doc # parse

        # host bindings
        if hostTriples = Triplr[@base.host]
          @base.send hostTriples, n, &f
        end

        # read JSON-LD
        n.css('script[type="application/ld+json"]').map{|dataElement|
          embeds << (::JSON::LD::API.toRdf ::JSON.parse dataElement.inner_text)} rescue "JSON-LD read failure in #{@base}"

        # read RDFa
        RDF::Reader.for(:rdfa).new(@doc, base_uri: @base){|_| embeds << _ } rescue "RDFa read failure in #{@base}"

        # normalized JSON-LD/RDFa
        embeds.each_triple{|s,p,o|
          p = MetaMap[p.to_s] || p
          puts [p, o].join "\t" unless p.to_s.match? /^(drop|http)/
          yield s, p, o unless p == :drop}

        # <link>
        n.css('head link[rel]').map{|m|
          if k = m.attr("rel") # predicate
            if v = m.attr("href") # object
              k = MetaMap[k] || ('#' + k.gsub(' ','_'))
              yield subject, k, v.R unless k == :drop
            end
          end}

        # <meta>
        n.css('head meta').map{|m|
          if k = (m.attr("name") || m.attr("property")) # predicate
            if v = m.attr("content")                    # object
              k = MetaMap[k] || k                  # normalize predicates
              case k                           # per-predicate custom processing
              when /lytics/
                k = :drop
              when 'https://twitter.com'
                v = ('https://twitter.com/' + v.sub(/^@/,'')).R
              when Abstract
                v = v.hrefs
              else
                v = HTML.webizeString v
                v = @base.join v if v.class == WebResource || v.class == RDF::URI
              end
                                # notify on predicates lacking HTTP mapping
              puts [k,v].join "\t" unless k.to_s.match? /^(drop|http)/
              yield subject, k, v unless k == :drop # meta-tag RDF
            end
          end}

        # <title>
        n.css('title').map{|title| yield subject, Title, title.inner_text }

        # <video>
        ['video[src]', 'video > source[src]'].map{|vsel|
          n.css(vsel).map{|v|
            yield subject, Video, v.attr('src').R }}

        # <body>
        if body = n.css('body')[0]
          %w{content-body entry-content}.map{|bsel|
            if content = body.css('.' + bsel)[0]
              yield subject, Content, HTML.clean(content.inner_html)
            end}
          [*BasicGunk,*Gunk].map{|selector|
            body.css(selector).map{|sel|
              #puts "X"*80,"stripping #{selector}:", sel
              sel.remove }} # strip elements
          yield subject, Content, HTML.clean(body.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        else # body element missing
          n.css('head').remove
          yield subject, Content, HTML.clean(n.inner_html).gsub(/<\/?(center|noscript)[^>]*>/i, '')
        end
      end
    end
  end
end

class WebResource
  module HTML

    Avatars = {}
    'avatars/*png'.R.glob.map{|a|
      Avatars[Base64.decode64(a.basename.split('.')[0]).downcase] = ServerAddr + a.path}

    def avatar link = nil
      location = ('avatars/' + Base64.encode64(uri).gsub("\n",'') + '.png').R
      location.writeFile open(link).read if link
      location
    end

    def self.colorize color = '#%06x' % (rand 16777216)
      "color: black; background-color: #{color}; border-color: #{color}"
    end

    # JSON-graph -> HTML
    def htmlDocument graph = {}

      # HEAD links
      @r ||= {}
      @r[:links] ||= {}
      @r[:images] ||= {}
      @r[:colors] ||= {}

      # title  TODO Canonicalize URIs in graphToTree? lookup all potential combinations here
      titleRes = [
        '#this', '',
        path && (path + '#this'), path,
        host && !path && ('//' + host + '#this'),
        host && !path && ('//' + host),
        host && path && ('https://' + host + path + '#this'),
        host && path && ('https://' + host + path),
        host && path && ('//' + host + path + '#this'),
        host && path && ('//' + host + path)
      ].compact.find{|u|
        graph[u] && graph[u][Title]}

      # render HEAD link as HTML
      link = -> key, displayname {
        if url = @r[:links][key]
          [{_: :a, href: url, id: key, class: :icon, c: displayname},
           "\n"]
          end}


      htmlGrep graph, q['q'] if @r[:grep]
      subbed = subscribed?
      tabular = env[:query]['view'] == 'table' || uri == '//www.w3.org/1999/02/22-rdf-syntax-ns'
      shrunken = env[:query].has_key? 'head'
      @r[:links][:up] = dirname + (dirname[-1] == '/' ? '' : '/') + qs + '#r' + Digest::SHA2.hexdigest(path||'/') unless !path || path == '/'
      @r[:links][:down] = path + '/' if env['REQUEST_PATH'] && node.directory? && env['REQUEST_PATH'][-1] != '/'

      # Markup -> HTML
      HTML.render ["<!DOCTYPE html>\n\n",
                   {_: :html,
                    c: [{_: :head,
                         c: [{_: :meta, charset: 'utf-8'},
                             ({_: :title, c: CGI.escapeHTML(graph[titleRes][Title].map(&:to_s).join ' ')} if titleRes),
                             {_: :style, c: ["\n", SiteCSS]}, "\n",
                             {_: :script, c: ["\n", SiteJS]}, "\n",
                             *@r[:links]&.map{|type,uri|
                                 {_: :link, rel: type, href: CGI.escapeHTML(uri.to_s)}}
                            ].map{|e|['  ',e,"\n"]}}, "\n\n",
                        {_: :body,
                         c: [{class: :toolbox,
                              c: [link[:up, '&#9650;'],
                                  {_: :a, id: :tabular, class: :icon, style: tabular  ? 'color: #fff' : 'color: #555', href: HTTP.qs(tabular  ? env[:query].reject{|k,v|k=='view'} : env[:query].merge({'view' => 'table', 'sort' => 'date'})), c: '↨'},
                                  {_: :a, id: :shrink,  class: :icon, style: shrunken ? 'color: #fff' : 'color: #555', href: HTTP.qs(shrunken ? env[:query].reject{|k,v|k=='head'} : env[:query].merge({'head' => ''})), c: shrunken ? '&#9661;' : '&#9651;'},
                                  unless local?
                                    [{_: :a, id: :ui, class: :icon, style: 'color: #555', href: HTTP.qs(env[:query].merge({'ui' => 'upstream'})), c: '⚗'},
                                     {_: :a, id: :subscribe, href: '/' + (subbed ? 'un' : '') + 'subscribe' + HTTP.qs({u: 'https://' + (host||env['SERVER_NAME']) + (@r['REQUEST_URI'] || path)}), class: subbed ? :on : :off, c: 'subscribe' + (subbed ? 'd' : '')}]
                                  end]},
                             link[:prev, '&#9664;'], link[:next, '&#9654;'],
                             if graph.empty?
                               HTML.keyval (Webize::HTML.webizeHash @r), @r # 404
                             elsif tabular
                               HTML.tabular graph, @r       # table
                             else
                               HTML.tree Treeize[graph], @r # tree
                             end,
                             link[:down,'&#9660;']]}]}]
    end

    # Markup -> HTML
    def self.render x
      case x
      when String
        x
      when Hash
        void = [:img, :input, :link, :meta].member? x[:_]
        '<' + (x[:_] || 'div').to_s +                        # open tag
          (x.keys - [:_,:c]).map{|a|                         # attr name
          ' ' + a.to_s + '=' + "'" + x[a].to_s.chars.map{|c| # attr value
            {"'"=>'%27', '>'=>'%3E', '<'=>'%3C'}[c]||c}.join + "'"}.join +
          (void ? '/' : '') + '>' + (render x[:c]) +         # child nodes
          (void ? '' : ('</'+(x[:_]||'div').to_s+'>'))       # close
      when Array
        x.map{|n|render n}.join
      when WebResource
        render [{_: :a, href: x.uri, id: 'l' + Digest::SHA2.hexdigest(rand.to_s), c: (%w{gif ico jpeg jpg png webp}.member?(x.ext.downcase) ? {_: :img, src: x.uri} : CGI.escapeHTML((x.query || (x.basename && x.basename != '/' && x.basename) || (x.path && x.path != '/' && x.path) || x.host || x.to_s)[0..48]))}, ' ']
      when NilClass
        ''
      when FalseClass
        ''
      else
        CGI.escapeHTML x.to_s
      end
    end
  end
end
