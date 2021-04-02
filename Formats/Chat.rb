class WebResource
  module HTML
    MarkupGroup[SIOC+'InstantMessage'] = -> msgs, env {
      msgs.group_by{|p|(p[To] || [''.R])[0]}.map{|to, msgs|
        msgs.map{|msg| msg.delete To}
        {class: :container,
         c: [{class: :head, c: to.R.display_name, _: :a, href: to},
             {class: :body, c: (HTML.tabular msgs, env)}]}
      }}
  end
end
