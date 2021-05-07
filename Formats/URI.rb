# coding: utf-8
require 'linkeddata'
class WebResource < RDF::URI
  module URIs

    GlobChars = /[\*\{\[]/

    LocalAddress = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).concat(ENV.has_key?('HOSTNAME') ? [ENV['HOSTNAME']] : []).uniq

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
    From     = Creator

    FOAF     = 'http://xmlns.com/foaf/0.1/'
    Person   = FOAF + 'Person'

    DOAP     = 'http://usefulinc.com/ns/doap#'
    OG       = 'http://ogp.me/ns#'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'

    def basename; File.basename path end

    def display_name
      return fragment if fragment && !fragment.empty?                    # fragment
      return query_values['id'] if queryvals.has_key? 'id'               # query
      return basename if path && basename && !['','/'].member?(basename) # basename
      return host.sub(/^www\./,'').sub(/\.com$/,'') if host              # hostname
      'user'
    end

    def ext; path ? (File.extname(path)[1..-1] || '') : '' end
    def suffix; '.' + ext end

    def host_parts
      local_node? ? ['.'] : host.split('.').-(%w(com net org www)).reverse
    end

    def insecure; ['http://', host, path, query].join.R env end

    def local_node?; !host || LocalAddress.member?(host) end

    def parts; path ? (path.split('/') - ['']) : [] end

    def queryvals
      return {} unless query
      (puts 'bad query: '+query; return {}) if query.match? /^&|&&|&$/ # TODO fix upstream URI library
      query_values
    end

  end

  alias_method :uri, :to_s

  # resource locator - derived from origin URI in proxy scenario
  def href
    if env.has_key?(:proxy_href) && !local_node? # proxy
      ['http://', env['HTTP_HOST'], '/', scheme ? nil : 'https:', uri].join
    else                                         # direct
      uri
    end
  end

  module HTML
    include URIs

    def uri_toolbar
      qs = queryvals
      bc = '' # breadcrumb trail
      favicon = ('//' + (host || 'localhost') + '/favicon.ico').R env # icon at well-known location
      icon = if env[:links][:icon]                       # icon reference in metadata
               env[:links][:icon] = env[:links][:icon].R env # use icon reference
               if env[:links][:icon].uri.index('data:') == 0 # data URI?
                 env[:links][:icon].uri                      # data URI
               else
                 if env[:links][:icon].path != favicon.path && !favicon.node.exist? && !favicon.node.symlink? # well-known location unlinked?
                   FileUtils.mkdir_p File.dirname favicon.fsPath
                   FileUtils.ln_s (env[:links][:icon].node.relative_path_from favicon.node.dirname), favicon.node # link to well-known location
                 end
                 env[:links][:icon].href                 # referenced icon
               end
             elsif favicon.node.exist?                   # icon at well-known location
               favicon.href
             end

      {class: :toolbox,
       c: [({_: :span, c: env[:status], style: 'font-weight: bold', class: :icon} if env[:status]),                                                              # status code
           ({_: :a, class: :icon, c: '↨', href: HTTP.qs(qs.merge({'view' => 'table', 'sort' => 'date'}))} unless env[:view] == 'table'),                         # link to tabular view
           {_: :a, href: (env[:proxy_href] && !local_node?) ? env[:base].uri : HTTP.qs(qs.merge({'notransform' => nil})), c: '⚗️', id: :UI, class: :icon},        # link to upstream UX
           ({_: :a,href: HTTP.qs(qs.merge({'download' => 'audio'})),c: '&darr;',class: :icon} if host&.match?(/(^|\.)(bandcamp|(mix|sound)cloud|youtube).com/)), # download link
           env[:feeds].map{|feed|                                                                                                                                # feed links
             {_: :a, href: feed.R(env).href,title: feed.path,class: :icon,c: FeedIcon}.update(feed.path.match?(/^\/feed\/?$/) ? {id: :sitefeed, style: 'border: .08em solid orange; background-color: orange'} : {})}, "\n",
           {_: :a, class: :host, href: env[:base].join('/').R(env).href, c: icon ? {_: :img, src: icon, style: DarkLogo.member?(host) ? 'background-color: #fff' : ''} : '🏠'},# link to path root
           {class: :path, c: env[:base].parts.map{|p| bc += '/' + p                                                                                              # path breadcrumbs
              {_: :a, class: :breadcrumb, href: env[:base].join(bc).R(env).href, c: [{_: :span, c: '/'}, (CGI.escapeHTML Rack::Utils.unescape p)]}}},
           (if SearchableHosts.member? host
            search_arg = %w(f find q search_query).find{|k|qs.has_key? k} || ([nil, '/'].member?(path) ? 'find' : 'q') # query argument
            qs[search_arg] ||= ''                                                                                      # initial query value
            {_: :form, c: qs.map{|k,v| ["\n", {_: :input, name: k, value: v}.update(k == search_arg ? {} : {type: :hidden})]}} # search box
            end), "\n"]}
    end
    
    # URI -> renderer lambda
    Markup = {}      # single resource of type
    MarkupGroup = {} # group of resources of type

    Markup['uri'] = -> uri, env {uri.R}

    MarkupGroup[Link] = -> links, env {
      links.map{|l|l.respond_to?(:R) ? l.R : l['uri'].R}.group_by{|l|links.size > 8 && l.host && l.host.split('.')[-1] || nil}.map{|tld, links|
        [{class: :container,
          c: [({class: :head, _: :span, c: tld} if tld),
              {class: :body, c: links.group_by{|l|links.size > 25 ? ((l.host||'localhost').split('.')[-2]||' ')[0] : nil}.map{|alpha, links|
                 ['<table><tr>',
                  ({_: :td, class: :head, c: alpha} if alpha),
                  {_: :td, class: :body,
                   c: {_: :table, class: :links,
                       c: links.group_by(&:host).map{|host, paths|
                         h = ('//' + (host || 'localhost')).R env
                         {_: :tr,
                          c: [{_: :td, class: :host,
                               c: host ? {_: :a, href: h.href, # id: 'host' + Digest::SHA2.hexdigest(rand.to_s),
                                          c: {_: :img, src: h.join('/favicon.ico').R(env).href},
                                          style: "background-color: #{HostColors[host] || '#ccc'}; color: black"} : []},
                              {_: :td, c: paths.map{|path|
                                 Markup[Link][path,env]}}]}}}},
                  '</tr></table>']}}]}, '&nbsp;']}}

    Markup[Link] = -> ref, env {
      u = ref.to_s
      re = u.R env
      [{_: :a, href: re.href, class: :path, c: (re.path||'/')[0..255]}, " \n"]}

  end
end

# #R method casts to WebResource (URI) from identifier
class RDF::URI
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class RDF::Node
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class String
  def R env=nil; env ? WebResource.new(self).env(env) : WebResource.new(self) end
end

class Symbol
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class WebResource
  def R env_=nil; env_ ? env(env_) : self end
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
        @base = options[:base_uri].R.path.sub(/.u$/,'').R
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
        @doc.lines.map(&:chomp).map{|line|
          unless line.empty? || line.match?(/^#/) # skip empty or commented lines
            uri, title = line.split ' ', 2        # URI and optional comment
            uri = uri.R                           # list-item resource
            fn.call RDF::Statement.new uri, Type.R, (Schema+'ListItem').R
            fn.call RDF::Statement.new uri, Title.R, title || uri.display_name
          end}
      end
    end
  end

end
