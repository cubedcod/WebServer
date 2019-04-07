# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    Hosts = {} # track hosts for highlighting

    def self.call env
      method = env['REQUEST_METHOD']                        # request-method
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? method # defined methods
      query = parseQs env['QUERY_STRING']                   # parse query
      host = query['host']|| env['HTTP_HOST']|| 'localhost' # lookup hostname
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse repeated slashes
      path  = Pathname.new(rawpath).expand_path.to_s        # evaluate path-expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/'  # preserve trailing-slash
      env[:Response] = {}; env[:links] = {}                 # init response-headers
      resource = ('//' + host + path).R env                 # bind resource and environment
      resource.send(method).do{|status,head,body|           # dispatch request
        # log request
        color = (if resource.env[:deny]
                 '31'
                elsif !Hosts.has_key? host # new host
                  Hosts[host] = true
                  '32'
                elsif method=='POST'
                  '32'
                elsif status==200
                  if resource.ext == 'js'
                    '36'
                  else
                    '37'
                  end
                else
                  '30'
                 end) + ';1'
        referer = env['HTTP_REFERER']
        referrer = if referer
                     r = referer.R
                     "\e[" + color + ";7m" + (r.host || '').sub(/^www\./,'').sub(/\.com$/,'') + "\e[0m -> "
                   else
                     ''
                   end
        location = head['Location'] ? (" -> " + head['Location']) : ""
        puts "\e[7m" + (method == 'GET' ? ' ' : '') + method + "\e[" + color + "m "  + status.to_s + "\e[0m " + referrer + ' ' +
             "\e[" + color + ";7mhttps://" + host + "\e[0m\e[" + color + "m" + path + resource.qs + "\e[0m" + location

        [status, head, body]} # response
    rescue Exception => e
      msg = [resource.uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      [500, {'Content-Type' => 'text/html'},
       [resource.htmlDocument(
          {resource.uri => {Content => [
                              {_: :style, c: "body {background-color: red !important}"}, {_: :h3, c: msg.hrefs},
                              {_: :pre, c: trace.hrefs},
                              (HTML.kv (HTML.urifyHash env), env)]}})]]
    end

    def deny
      env[:deny] = true
      [200, {'Content-Type' => ext=='js' ? 'application/javascript' : 'text/plain'}, []]
    end

    def environment env = nil
      if env
        @r = env
        self
      else
        @r || {}
      end
    end
    alias_method :env, :environment

    def GET
      return PathGET[path][self] if PathGET[path] # path lambda
      return HostGET[host][self] if HostGET[host] # host lambda
      return chronoDir           if chronoDir?    # time redirect
      return localNode           if localNode?
      return case env['HTTP_TYPE']
             when /nofetch/
               deny
             when /filter/
               remoteFiltered
             end if env.has_key? 'HTTP_TYPE'
      remoteNode
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    def notfound
      dateMeta # page hints as something nearby may exist
      [404,{'Content-Type' => 'text/html'},[htmlDocument]]
    end

    def OPTIONS
      return HostOPTIONS[host][self] if HostOPTIONS[host]
      env[:deny] = true
      [202,{},[]]
    end

    # String -> Hash
    def HTTP.parseQs qs
      if qs
        h = {}
        qs.split(/&/).map{|e|
          k, v = e.split(/=/,2).map{|x|CGI.unescape x}
          h[(k||'').downcase] = v}
        h
      else
        {}
      end
    end

    def POST
      return PathPOST[path][self] if PathPOST[path]
      return HostPOST[host][self] if HostPOST[host]
      trackPOST
    end

    def PUT
      [202,{},[]]
    end

    # parsed query-string as Hash
    def q
      @q ||= HTTP.parseQs qs[1..-1]
    end

    # query-string
    def qs
      if @r && @r['QUERY_STRING'] && !@r['QUERY_STRING'].empty?
        '?' +  @r['QUERY_STRING']
      elsif        query          && !query.empty?
        '?' +      query
      else
        ''
      end
    end

    # Hash -> String
    def HTTP.qs h
      '?' + h.map{|k,v|
        k.to_s + '=' + (v ? (CGI.escape [*v][0].to_s) : '')
      }.intersperse("&").join('')
    end

    Response_204 = [204, {'Content-Length' => 0}, []]

  end
  include HTTP
end
