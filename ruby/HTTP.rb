# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    Hosts = {} # track hosts for highlighting
    HostFirsts = []

    def cache?; !(pragma && pragma == 'no-cache') end

    def self.call env
      method = env['REQUEST_METHOD']                        # request-method
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? method # defined methods
      query = env[:query] = parseQs env['QUERY_STRING']     # query
      host = env['HTTP_HOST']|| 'localhost'                 # host name
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse consecutive path-sep chars
      path  = Pathname.new(rawpath).expand_path.to_s        # evaluate path expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/'  # preserve trailing-slash
      resource = ('//' + host + path).R env                 # request environment
      env[:Response] = {}; env[:links] = {}                 # response environment
      # dispatch request
      resource.send(method).do{|status,head,body|
        # log to console
        color = (if resource.env[:deny]
                 '31'
                elsif !Hosts.has_key? host # first-seen host
                  Hosts[host] = true
                  HostFirsts.unshift resource.uri
                  '32'
                elsif method=='POST'
                  '32'
                elsif status==200
                  if resource.ext == 'js' || (head['Content-Type'] && head['Content-Type'].match?(/script/))
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
        relocation = head['Location'] ? (" ↝ " + head['Location']) : ""
        puts "\e[7m" + (method == 'GET' ? '' : method) + "\e[" + color + "m "  + status.to_s + "\e[0m " + referrer + ' ' +
             "\e[" + color + ";7mhttps://" + host + "\e[0m\e[" + color + "m" + path + resource.qs + "\e[0m " + (env['HTTP_TYPE'] || '') + relocation

        # response
        [status, head, body]}
    rescue Exception => e
      msg = [resource.uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      [500, {'Content-Type' => 'text/html'},
       [resource.htmlDocument(
          {resource.uri => {Content => [
                              {_: :h3, c: msg.hrefs, style: 'color: red'},
                              {_: :pre, c: trace.hrefs},
                              (HTML.kv (HTML.urifyHash env), env),
                              (HTML.kv (HTML.urifyHash e.io.meta), env if e.respond_to? :io)]}})]]
    end

    def deny
      env[:deny] = true
      js = ext == 'js'
      [200, {'Content-Type' => js ? 'application/javascript' : 'text/html; charset=utf-8'},
       js ? [] : ["<html><body style='background-color: red; text-align: center'><span style='color: #fff; font-size: 28em'>⌘</span></body></html>"]]
    end
    alias_method :drop, :deny

    def denyPOST
      head = HTTP.unmangle env
      body = env['rack.input'].read
      body = if head['Content-Encoding'].to_s.match?(/zip/)
               Zlib::Inflate.inflate(body) rescue ''
             else
               body
             end
      HTTP.print_body body, head['Content-Type'] unless host.match? /google|instagram|youtube/
      env[:deny] = true
      [202,{},[]]
    end

    def echo
      [200, {'Content-Type' => 'text/html'}, [htmlDocument]]
    end

    def entity env, lambda = nil
      etags = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ }
      if etags && (etags.include? env[:Response]['ETag'])
        [304, {}, []] # client has entity
      else
        body = lambda ? lambda.call : self # generate
        if body.class == WebResource # body as resource reference
          # use Rack file handling
          (Rack::File.new nil).serving((Rack::Request.new env),body.localPath).do{|s,h,b|
            [s,h.update(env[:Response]),b]}
        else
          [(env[:Status]||200), env[:Response], [body]]
        end
      end
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
      return [204,{'Content-Length'=>0},[]] if path.match? /204$/
      return PathGET[path][self] if PathGET[path] # path lambda
      return HostGET[host][self] if HostGET[host] # host lambda
      local || remote
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    def local
      localNode if localNode?
    end

    # file(s) -> HTTP Response
    def localGraph
      graphResponse localNodes
    end

    def localNode
      if %w{y year m month d day h hour}.member? parts[0] # local timeline
        time = Time.now
        loc = time.strftime(case parts[0][0].downcase
                            when 'y'
                              '/%Y/'
                            when 'm'
                              '/%Y/%m/'
                            when 'd'
                              '/%Y/%m/%d/'
                            when 'h'
                              '/%Y/%m/%d/%H/'
                            else
                            end)
        [303, @r[:Response].update({'Location' => loc + parts[1..-1].join('/') + qs}), []]
      elsif file?
        localFile
      else
        localGraph
      end
    end

    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq

    def localNode?
      LocalAddr.member? @r['SERVER_NAME']
    end

    PathGET['/log'] = -> r {
      graph = {}
      HostFirsts.map{|uri|
        u = uri.R
        path = '/' + u.host.split('.').reverse.map{|n|n.split '-'}.flatten.join('/')
        graph[path] = {'uri' => path, Link => ('//' + u.host).R}}
      [200, {'Content-Type' => 'text/html'}, [r.htmlDocument(graph)]]}

    def notfound
      dateMeta # nearby page may exist, search for pointers
      [404,{'Content-Type' => 'text/html'},[htmlDocument]]
    end

    def OPTIONS
      if host.match? POSThosts
        self.OPTIONSthru
      else
        env[:deny] = true
        [202,{},[]]
      end
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
      if host.match? POSThosts
        sitePOST
      else
        denyPOST
      end
    end

    def pragma; env['HTTP_PRAGMA'] end

    def PUT
      env[:deny] = true
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
      elsif query && !query.empty?
        '?' + query
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

    # ALL_CAPS (CGI/env-var) key-names to standard HTTP capitalization
    # ..is there any way to have Rack give us the names straight out of the HTTP parser?
    def self.unmangle env
      head = {}
      env.map{|k,v|
        k = k.to_s
        underscored = k.match? /(_AP_|PASS_SFP)/i
        key = k.downcase.sub(/^http_/,'').split('_').map{|k| # eat prefix and process tokens
          if %w{cl id spf utc xsrf}.member? k # acronyms
            k = k.upcase
          else
            k[0] = k[0].upcase # capitalize word
          end
          k
        }.join(underscored ? '_' : '-')
        key = key.downcase if underscored
        # strip internal headers
        head[key] = v.to_s unless %w{links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}
      head
    end

  end
  include HTTP
end
