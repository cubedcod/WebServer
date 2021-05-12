class WebResource
  module HTML

    MarkupGroup[LDP+'Container'] = -> dirs, env {
      if env[:view] == 'table'
        HTML.tabular dirs, env
      else
        dirs.map{|d|
          Markup[LDP+'Container'][d, env]}
      end}

    Markup[LDP+'Container'] = -> dir, env {
      uri = (dir.delete('uri') || env[:base]).R env
      [Type, Title,
       W3 + 'ns/posix/stat#mtime',
       W3 + 'ns/posix/stat#size'].map{|p|dir.delete p}
      {class: :container,
       c: [{_: :a, id: 'container' + Digest::SHA2.hexdigest(rand.to_s), class: :head, href: uri.href, c: uri.basename},
           {class: :body, c: HTML.keyval(dir, env)}]}}

    Markup[Stat+'File'] = -> file, env {
      [({class: :file,
         c: [{_: :a, href: file['uri'], class: :icon, c: Icons[Stat+'File']},
             {_: :span, class: :name, c: file['uri'].R.basename}]} if file['uri']),
       (HTML.keyval file, env)]}

  end
end
