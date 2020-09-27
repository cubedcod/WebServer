# coding: utf-8
require 'linkeddata'
class WebResource < RDF::URI

  module URIs

    GlobChars = /[\*\{\[]/

    # common URIs

    W3       = 'http://www.w3.org/'
    Atom     = W3 + '2005/Atom#'
    LDP      = W3 + 'ns/ldp#'
    List     = W3 + '1999/02/22-rdf-syntax-ns#List'
    RDFs     = W3 + '2000/01/rdf-schema#'
    Stat     = W3 + 'ns/posix/stat#'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'

    DC       = 'http://purl.org/dc/terms/'
    Abstract = DC + 'abstract'
    Audio    = DC + 'Audio'
    Date     = DC + 'date'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Title    = DC + 'title'
    Video    = DC + 'Video'

    SIOC     = 'http://rdfs.org/sioc/ns#'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    To       = SIOC + 'addressed_to'
    Post     = SIOC + 'Post'

    FOAF     = 'http://xmlns.com/foaf/0.1/'
    Person   = FOAF + 'Person'

    DOAP     = 'http://usefulinc.com/ns/doap#'
    OG       = 'http://ogp.me/ns#'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'

    def basename; File.basename path end

    def display_name
      return fragment if fragment && !fragment.empty?
      return basename if path && basename && !['','/'].member?(basename)
      return host.sub(/^www\./,'').sub(/\.com$/,'') if host
      'user'
    end

    def ext; path ? (File.extname(path)[1..-1] || '') : '' end
    def extension; '.' + ext end

    def parts; path ? (path.split('/') - ['']) : [] end

    def query_hash
      return '' unless query && !query.empty?
      '.' + Digest::SHA2.hexdigest(query)[0..15]
    end

  end

  alias_method :uri, :to_s

  module HTML
    include URIs

    def uri_toolbar
      qs = query_values || {}
      bc = '' # breadcrumb trail
      favicon = ('//' + host + '/favicon.ico').R
      icon = if env[:links][:icon]                                                                          # icon reference provided in upstream HTML
               env[:links][:icon] = env[:links][:icon].R
               if env[:links][:icon].path != favicon.path && !favicon.node.exist? && !favicon.node.symlink? # icon at non-default location
                 FileUtils.mkdir_p File.dirname favicon.fsPath
                 FileUtils.ln_s (env[:links][:icon].node.relative_path_from favicon.node.dirname), favicon.node # link to default location
               end
               env[:links][:icon].href                                                                      # referenced icon
             elsif favicon.node.exist?                                                                      # host icon exists?
               favicon.href                                                                                 # host icon
             else                                                                                           # default icon
               '/favicon.ico'
             end
      {class: :toolbox,
       c: [({_: :span, c: env[:origin_status], style: 'font-weight: bold', class: :icon} if env[:origin_status]),
           ({_: :a, id: :tabular, class: :icon, c: '↨', href: env[:base].join(HTTP.qs(qs.merge({'view' => 'table', 'sort' => 'date'}))).R.href} unless qs['view'] == 'table'),
           {_: :a, href: env[:base].uri, c: '☝', class: :icon, id: :upstream},
           ({_: :a, href: HTTP.qs(qs.merge({'notransform' => nil})), c: '⚗️', id: :UI, class: :icon} unless local_node?),
           ({_: :a, href: HTTP.qs(qs.merge({'download' => 'audio'})), c: '&darr;', id: :download, class: :icon} if host.match?(/(^|\.)(bandcamp|(mix|sound)cloud|youtube).com/)),
           {_: :a, href: env[:base].join('/').R.href, id: :host, c: {_: :img, src: icon, style: 'z-index: -1'}},
           {class: :path,
            c: env[:base].parts.map{|p| bc += '/' + p
              {_: :a, class: :breadcrumb, href: env[:base].join(bc).R.href, c: [{_: :span, c: '/'}, (CGI.escapeHTML Rack::Utils.unescape p)], id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}}},
           env[:feeds].map{|feed|
             {_: :a, href: feed.R.href, title: feed.path, class: :icon, c: FeedIcon, id: 'feed' + Digest::SHA2.hexdigest(feed.to_s)}.update(feed.path.match?(/^\/feed\/?$/) ? {style: 'border: .1em solid orange; background-color: orange'} : {})}, "\n",
           (search_arg = %w(f find q search_query).find{|k|qs.has_key? k} || ([nil, '/'].member?(path) ? 'find' : 'q') # query arg
            qs[search_arg] ||= ''                                                                                      # initialize query field
            {_: :form, c: qs.map{|k,v|
               ["\n", {_: :input, name: k, value: v}.update(k == search_arg ? ((env[:searchable] && v.empty?) ? {autofocus: true} : {}) : {type: :hidden})]}}.update(env[:search_base] ? {action: env[:base].join(env[:search_base]).R.href} : {})), "\n"]}
    end
    
    # URI -> markup-lambda index
    Markup = {}
    MarkupGroup = {}

    Markup['uri'] = -> uri, env {uri.R}

  end

  module HTTP

    def allow_domain?
      c = AllowDomains                                              # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

    def deny?
      return true if deny_domain?
      return true if uri.match? Gunk
      false
    end

    def deny_domain?
      return false if !host || WebResource::HTTP::HostGET.has_key?(host) || allow_domain?
      c = DenyDomains                                               # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # search for leaf in domain tree
    end

  end
end

# cast-method to a WebResource
class Hash
  def R env=nil; env ? WebResource.new(self['uri']).env(env) : WebResource.new(self['uri']) end
end
class Pathname
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end
class RDF::URI
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end
class RDF::Node
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end
class String
  def R env=nil; env ? WebResource.new(self).env(env) : WebResource.new(self) end
end
class WebResource
  def R env_=nil; env_ ? env(env_) : self end
end
