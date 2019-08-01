# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # graph(s) -> file(s)
  def index g
    updates = []
    g.each_graph.map{|graph|
      if n = graph.name
        n = n.R
        docs = []
        # local docs are already stored on timeline (mails/chatlogs in hour-dirs), so we only try for canonical location
        docs.push (n.path + '.ttl').R unless n.host || n.uri.match?(/^_:/)                                     # canonical location
        if n.host && (timestamp=graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value) # timeline location
          docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),       # hour-dir
                     %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # slugs
                      flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist
        end
        # store
        #puts docs
        docs.map{|doc|
          unless doc.exist?
            doc.dir.mkdir
            RDF::Writer.open(doc.relPath){|f|f << graph}
            updates << doc
            puts  "\e[32m+\e[0m " + ServerAddr + doc.path.sub(/\.ttl$/,'')
          end}
      end}
    updates
  end

  # file -> graph
  def load graph, options = {}
    if basename.split('.')[0] == 'msg'
      options[:format] = :mail
    elsif ext == 'html'
      options[:format] = :html
    elsif %w(Cookies).member? basename
      options[:format] = :sqlite
    end
    #puts "load #{relPath}"
    graph.load relPath, options
  end

  # graph -> Hash
  def treeFromGraph graph ; tree = {}
    head = q.has_key? 'head'
    graph.each_triple{|s,p,o|
      s = s.to_s; p = p.to_s # subject URI, predicate URI
      unless head && p == Content
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        tree[s][p].push o unless tree[s][p].member? o # object
      end}
    @r[:graph] = tree
    tree
  end

  module HTML

    def self.keyval t, env
      {_: :table, class: :kv,
       c: t.map{|k,vs|
         vs = (vs.class == Array ? vs : [vs]).compact
         type = (k ? k.to_s : '#notype').R
         ([{_: :tr, name: type.fragment || type.basename,
            c: [{_: :td, class: 'k', c: Markup[Type][type]},
                {_: :td, class: 'v', c: vs.map{|v|
                   [(value k, v, env), ' ']}}]}, "\n"] unless k=='uri' && vs[0] && vs[0].to_s.match?(/^_:/))}}
    end

    def self.tabular graph, env
      graph = graph.values if graph.class == Hash
      keys = graph.map{|resource|resource.keys}.flatten.uniq - [Abstract, Content, DC+'hasFormat', DC+'identifier', Image, Video, SIOC+'reply_of', SIOC+'user_agent', Title, Type]
      if env[:query] && env[:query].has_key?('sort')
        attr = env[:query]['sort']
        attr = Date if attr == 'date'
        graph = graph.sort_by{|r|
          if values = r[attr]
            values[0].to_s
          else
            ''
          end
         }.reverse
      end
      titles = {}
      {_: :table, class: :tabular,
       c: [{_: :tr, c: keys.map{|p|
              p = p.R
              slug = p.fragment || p.basename
              icon = Icons[p.uri] || slug
              {_: :td, c: (env[:query]||{})['sort'] == p.uri ? icon : {_: :a, class: :head, id: 'sort_by_' + slug, href: '?view=table&sort='+CGI.escape(p.uri), c: icon}}}},
           graph.map{|resource|
             contentRow = resource[Abstract] || resource[Content] || resource[Image] || resource[Video]
             [{_: :tr, c: keys.map{|k|
                 {_: :td,
                  c: if k == 'uri'
                   ts = resource[Title] || []
                   if ts.size > 0
                     ts.map{|t|
                       title = t.to_s.sub(/\/u\/\S+ on /,'')
                       if titles[title]
                         {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :id, c: '☚'}
                       else
                         titles[title] = true
                         {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :title,
                          c: [(CGI.escapeHTML title), ' ',
                              #{_: :span, class: :uri, c: CGI.escapeHTML(resource['uri'][0..96])},
                              ' ']}
                       end}
                   else
                     {_: :a, href: resource['uri'], id: 'r' + Digest::SHA2.hexdigest(rand.to_s), class: :id, c: '&#x1f517;'}
                   end
                 else
                   (resource[k]||[]).map{|v|value k, v, env }
                  end}}}.update(resource['uri'] && resource['uri'].R.path == env['REQUEST_PATH'] && {id: resource['uri'].R.fragment} || {}),
              ({_: :tr, c: {_: :td, colspan: keys.size,
                            c: [resource[Abstract] ? [resource[Abstract], '<br>'] : '',
                                (resource[Image]||[]).map{|i| {style: 'max-width: 28em', c: Markup[Image][i,env]}},
                                (resource[Video]||[]).map{|i| {style: 'max-width: 32em', c: Markup[Video][i,env]}},
                                resource[Content]]}} if contentRow)]}]}
    end

    def self.tree t, env, name=nil
      url = t[:RDF]['uri'] if t[:RDF]
      if name && t.keys.size > 1
        color = '#%06x' % rand(16777216)
        scale = rand(7) + 1
        position = scale * rand(960) / 960.0
        css = {style: "border: .08em solid #{color}; background: repeating-linear-gradient(#{rand 360}deg, #000, #000 #{position}em, #{color} #{position}em, #{color} #{scale}em)"}
      end
      {class: :tree,
       c: [({_: :a, href: url, c: CGI.escapeHTML(name.to_s[0..85])} if name && url),
           t.map{|_name, _t|
             _name == :RDF ? (value nil, _t, env) : (tree _t, env, _name)}]}.update(css ? css : {})
    end

    # Markup dispatcher
    def self.value type, v, env
      if Abstract == type || Content == type
        v
      elsif Markup[type] # supplied type argument
        Markup[type][v,env]
      elsif v.class == Hash # RDF type
        # TODO just render resource (potentially N times) for each type with a defined renderer?
        # could simplify this but we'd still need deduplication and type-merging logic
        types = (v[Type]||[]).map &:R
        if (types.member? Post) || (types.member? SIOC+'BlogPost') || (types.member? SIOC+'MailMessage') || (types.member? Schema+'DiscussionForumPosting') || (types.member? Schema+'Answer') || (types.member? Schema+'Review') || (types.member? 'https://schema.org/Comment') || (types.member? Schema+'NewsArticle')
          Markup[SIOC+'MailMessage'][v,env]
        elsif (types.member? Image) || (types.member? Schema+'ImageObject') || (types.member? 'https://schema.org/ImageObject')
          Markup[Image][v,env]
        elsif types.member? LDP+'Container'
          Markup[LDP+'Container'][v,env]
        elsif types.member? Stat+'File'
          Markup[Stat+'File'][v,env]
        elsif (types.member? Schema+'BreadcrumbList') || (types.member? 'https://schema.org/BreadcrumbList')
          Markup[Schema+'BreadcrumbList'][v,env]
        elsif (types.member? SIOC+'UserAccount') || (types.member? Schema+'Person') || (types.member? 'https://schema.org/Person')
          Markup[SIOC+'UserAccount'][v,env]
        else
          keyval v, env
        end
      elsif v.class == WebResource
        if v.uri.match?(/^_:/) && env[:graph] && env[:graph][v.uri] # blank-node
          value nil, env[:graph][v.uri], env
        elsif %w{jpeg jpg JPG png PNG webp}.member? v.ext           # image
          Markup[Image][v, env]
        else
          v
        end
      else # undefined
        CGI.escapeHTML v.to_s
      end
    end

    Treeize = -> graph {
      tree = {}
      # visit nodes
      (graph.class == Array ? graph : graph.values).map{|node|
        re = (node['uri'] || '').R
        # traverse
        cursor = tree
        [re.host ? re.host.split('.').reverse : nil, re.parts, re.qs, re.fragment].flatten.compact.map{|name|
          cursor = cursor[name] ||= {}}
        if cursor[:RDF] # merge to existing node
          node.map{|k,v|
            unless k == 'uri'
              if cursor[:RDF][k]
                cursor[:RDF][k].concat v # merge value-lists
              else
                cursor[:RDF][k] = v # new key
              end
            end}
        else
          cursor[:RDF] = node # new node
        end}
      tree }

    Markup[Type] = -> t, env=nil {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || t.basename}.update(Icons[t.uri] ? {} : {style: 'font-weight: bold'})
      else
        CGI.escapeHTML t.to_s
      end}
  end
end
module Webize
  module URIlist
    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'

      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].path.sub(/.u$/,'').R
        @doc = input.respond_to?(:read) ? input.read : input
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
        fn.call RDF::Statement.new(@base, Type.R, (Schema+'BreadcrumbList').R)
        @doc.lines.map{|line|
          fn.call RDF::Statement.new(@base, ('https://schema.org/itemListElement').R, line.chomp.R)}
      end
    end
  end
end
