class WebResource
  module HTML
    MarkupGroup[SIOC+'InstantMessage'] = -> msgs, env {
      msgs.group_by{|p|(p[To] || [''.R])[0]}.map{|to, msgs|
        msgs.map{|msg| msg.delete To}
        HTML.tabular msgs, env
      }}
  end
end
