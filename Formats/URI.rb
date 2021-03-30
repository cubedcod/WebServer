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
    def extension; '.' + ext end

    def host_parts
      local_node? ? ['.'] : host.split('.').-(%w(com net org www)).reverse
    end

    def insecure; ['http://', host, path, query].join.R env end

    def local_node?; !host || LocalAddress.member?(host) end

    def parts; path ? (path.split('/') - ['']) : [] end

    def queryvals
      return {} unless query
      (puts 'bad query: '+query; return {}) if query.match? /^&|&$/ # TODO fix upstream URI library
      query_values
    end

  end

  alias_method :uri, :to_s

  def href
    env.has_key?(:proxy_href) ? proxy_href : uri
  end

  # rebase href on local host
  def proxy_href
    return self if local_node? # local node, no proxying
    ['http://', env['HTTP_HOST'], '/', host, path, (query ? ['?', query] : nil), (fragment ? ['#', fragment] : nil) ].join
  end

  module HTML
    include URIs

    def uri_toolbar
      qs = query_values || {}
      bc = '' # breadcrumb trail
      favicon = ('//' + host + '/favicon.ico').R env # icon at well-known location
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
       c: [({_: :span, c: env[:status], style: 'font-weight: bold', class: :icon} if env[:status]),                                                                            # status code
           ({_: :a, id: :tabular, class: :icon, c: '↨', href: env[:base].join(HTTP.qs(qs.merge({'view' => 'table', 'sort' => 'date'}))).R.href} unless env[:view] == 'table'), # link to tabular view
           {_: :a, href: (env[:proxy_href] && !local_node?) ? env[:base].uri : HTTP.qs(qs.merge({'notransform' => nil})), c: '⚗️', id: :UI, class: :icon},                      # link to upstream UI and/or format
           ({_: :a, href: HTTP.qs(qs.merge({'download' => 'audio'})), c: '&darr;', id: :download, class: :icon} if host.match?(/(^|\.)(bandcamp|(mix|sound)cloud|youtube).com/)), # download link
           env[:feeds].map{|feed|                                                                                                                                                 # feed links
             {_: :a, href: feed.R.href, title: feed.path, class: :icon, c: FeedIcon, id: 'feed' + Digest::SHA2.hexdigest(feed.to_s)}.update(feed.path.match?(/^\/feed\/?$/) ? {style: 'border: .08em solid orange; background-color: orange'} : {})}, "\n",
           {_: :a, href: env[:base].join('/').R.href, id: :host, c: icon ? {_: :img, src: icon, style: DarkLogo.member?(host) ? 'background-color: #fff' : ''} : '🏠'},        # link to path root
           {class: :path, c: env[:base].parts.map{|p| bc += '/' + p                                                                                                            # path breadcrumbs
              {_: :a, class: :breadcrumb, href: env[:base].join(bc).R.href, c: [{_: :span, c: '/'}, (CGI.escapeHTML Rack::Utils.unescape p)], id: 'r' + Digest::SHA2.hexdigest(rand.to_s)}}},
           (if SearchableHosts.member? host
            search_arg = %w(f find q search_query).find{|k|qs.has_key? k} || ([nil, '/'].member?(path) ? 'find' : 'q') # query argument
            qs[search_arg] ||= ''                                                                                      # initial query value
            {_: :form, c: qs.map{|k,v| ["\n", {_: :input, name: k, value: v}.update(k == search_arg ? {} : {type: :hidden})]}} # search box
            end), "\n"]}
    end
    
    # URI -> lambda
    Markup = {}      # markup single resource of type
    MarkupGroup = {} # markup group of resources of type

    Markup['uri'] = -> uri, env {uri.R}

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
        @doc.lines.map(&:chomp).map(&:strip).map{|line|
          fn.call RDF::Statement.new line.R, Type.R, (W3 + '2000/01/rdf-schema#Resource').R unless line.empty? || line.match?(/^#/)}
      end
    end
  end

end
