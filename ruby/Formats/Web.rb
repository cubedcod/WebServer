# coding: utf-8
module Webize
  module WebForm
    class Format < RDF::Format
      content_type 'application/x-www-form-urlencoded'
      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @subject = (options[:base_uri] || '#form').R 
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
    Markup['uri'] = -> uri, env=nil {uri.R}

    Markup[Date] = -> date, env=nil {
      {_: :a, class: :date, href: (env && %w{l localhost}.member?(env['SERVER_NAME']) && '/' || 'http://localhost:8000/') + date[0..13].gsub(/[-T:]/,'/'), c: date}}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      avatar = Avatars[u.downcase.gsub(/\/$/,'')]
      [{_: :a,
        c: avatar ? {_: :img, class: :avatar, src: avatar} : u.sub(/^https?.../,'')[0..79],
        href: u,
        id: 'l' + Digest::SHA2.hexdigest(rand.to_s),
        style: avatar ? 'background-color: #000' : (env[:colors][u.R.host] ||= HTML.colorize),
        title: u,
       },
       " \n"]}

    Markup[Schema+'BreadcrumbList'] = -> list, env {
      {class: :list,
       c: tabular((list[Schema+'itemListElement']||
                   list['https://schema.org/itemListElement']||[]).map{|l|
                    env[:graph][l.uri] || (l.class == WebResource ? {'uri' => l.uri,
                                                                     Title => [l.uri]} : l)}, env)}}
    Markup[SIOC+'UserAccount'] = -> user, env {
      if u = user['uri']
        {class: :user,
         c: [(if avatar = Avatars[u.downcase]
              {_: :img, src: avatar}
             else
               {_: :span, c: '👤'}
              end),
             (HTML.keyval user, env)]}
      else
        puts :useraccount, user
      end
    }

  end
end
