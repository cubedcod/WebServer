# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    Hosts = {} # track seen hosts for new-host highlighting in logger

    def self.call env
      method = env['REQUEST_METHOD']                        # request-method
      return [405,{},[]] unless %w{GET HEAD OPTIONS PUT POST}.member? method # defined methods
      query = parseQs env['QUERY_STRING']                   # parse query
      host = query['host']|| env['HTTP_HOST']|| 'localhost' # find hostname
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse consecutive slashes
      path  = Pathname.new(rawpath).expand_path.to_s        # evaluate path-expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/'  # trailing-slash preservation
      env[:Response] = {}; env[:links] = {}                 # response-header storage
      resource = ('//' + host + path).R env                 # bind resource and environment
      resource.send(method).do{|status,head,body|           # dispatch request

        # logging
        color = (if resource.env[:deny]
                 '31'
                elsif !Hosts.has_key? host
                  Hosts[host] = true
                  '32'
                elsif method=='POST'
                  '32'
                elsif status==200
                  '37'
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
    rescue Exception => x
      msg = [x.class,x.message,x.backtrace].join "\n"
      puts msg
      [500, {'Content-Type'=>'text/plain'}, method=='HEAD' ? [] : [msg]]
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
      return chronoDir if chronoDir?              # timeslice container
      return fileResponse if node.file?           # local static-resource
      return graphResponse localNodes if localResource? # local resource
      return case env['HTTP_TYPE'] # typed request
             when /AMP/ # accelerated mobile page
               amp
             when /feed/ # RSS/Atom feed
               remoteNode
             when /short/ # shortened URL
               cachedRedirect
             when /noexec/ # remote data file
               remoteFile
             when /hosted/ # listed host
               if ('/' + host).R.exist? # host-dir exists?
                 remoteNode # remote resource
               else
                 deny # host-dir required
               end
             else # undefined request-type
               deny
             end if env.has_key? 'HTTP_TYPE'
      remoteNode # local handling undefined -> remote resource
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

    def pragma; env['HTTP_PRAGMA'] end

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

    # ALL_CAPS CGI/env-vars to HTTP request-header capitalization
    # is there any way to get the unmangled data from rack?
    def self.unmangle env
      head = {}
      env.map{|k,v|
        key = k.to_s.downcase.sub(/^http_/,'').split('_').map{|k| # chop prefix and tokenize
          if %w{cl id spf utc xsrf}.member? k # acronyms to capitalize
            k = k.upcase
          else
            k[0] = k[0].upcase # word
          end
          k
        }.join '-'
        # headers for request. drop rack-internal and Type, our typetag. Host is added by fetcher and may vary from current environment
        head[key] = v.to_s unless %w{accept-encoding host links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software type unicorn.socket upgrade-insecure-requests version via x-forwarded-for}.member?(key.downcase)}
      head
    end

  end
  include HTTP
end
