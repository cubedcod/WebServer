# coding: utf-8
class WebResource
  module HTTP
    include MIME
    include URIs

    def cache?; !(pragma && pragma == 'no-cache') end

    def self.call env
      method = env['REQUEST_METHOD']                        # request-method
      return [202,{},[]] unless Methods.member? method      # undefined method
      query = parseQs env['QUERY_STRING']                   # parse query
      host = query['host']|| env['HTTP_HOST']|| 'localhost' # find hostname
      rawpath = env['REQUEST_PATH'].force_encoding('UTF-8').gsub /[\/]+/, '/' # collapse consecutive slashes
      path  = Pathname.new(rawpath).expand_path.to_s        # evaluate path-expression
      path += '/' if path[-1] != '/' && rawpath[-1] == '/'  # trailing-slash preservation
      env[:Response] = {}; env[:links] = {}                 # response-header storage
      resource = ('//' + host + path).R env                 # bind resource and environment
      resource.send(method).do{|status,head,body|           # dispatch request
        # log response
        color = (if resource.env[:deny]
                 '31'
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
        puts "\e[7m" + (method == 'GET' ? ' ' : '') + method + "\e[" + color + "m "  + status.to_s + "\e[0m " +
             referrer + (env['HTTP_TYPE'] || '') + ' ' + "\e[" + color + ";7mhttps://" +
             host + "\e[0m\e[" + color + "m" + path + resource.qs + "\e[0m" + location

        # response
        [status, head, body]}
    rescue Exception => x
      [500, {'Content-Type'=>'text/plain'}, method=='HEAD' ? [] : [[x.class,x.message,x.backtrace].join("\n")]]
    end

    def cdn
      if %w{html jpg jpeg ogg m3u8 m4a mp3 mp4 png ts webm webp}.member? ext.downcase
        remoteNode
      else
        deny
      end
    end

    def chronoDir?
      (parts[0]||'').match /^(y(ear)?|m(onth)?|d(ay)?|h(our)?)$/i
    end

    def chronoDir
      time = Time.now
      loc = time.strftime(case parts[0][0].downcase
                          when 'y'
                            '%Y'
                          when 'm'
                            '%Y/%m'
                          when 'd'
                            '%Y/%m/%d'
                          when 'h'
                            '%Y/%m/%d/%H'
                          else
                          end)
      [303, @r[:Response].update({'Location' => '/' + loc + '/' + parts[1..-1].join('/') + qs}), []]
    end

    def deny
      env[:deny] = true
      [200, {'Content-Type' => ext=='js' ? 'application/javascript' : 'text/plain'}, []]
    end

    # conditional responder
    def entity env, lambda = nil
      etags = env['HTTP_IF_NONE_MATCH'].do{|m| m.strip.split /\s*,\s*/ }
      if etags && (etags.include? env[:Response]['ETag'])
        [304, {}, []] # client has entity
      else
        body = lambda ? lambda.call : self # response body
        if body.class == WebResource # resource reference
          # dispatch to file handler
          (Rack::File.new nil).serving((Rack::Request.new env),body.localPath).do{|s,h,b| # response
            [s,h.update(env[:Response]),b]} # attach metadata and return
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
      # path-lambda binding
      return PathGET[path][self] if PathGET[path]
      # host-lambda binding
      return HostGET[host][self] if HostGET[host]
      # type-tagged request
      return case env['HTTP_TYPE']
             when /AMP/ # redirect to canonical page
               amp
             when /CDN/ # static cache
               cdn
             when /feed/ # Feed URL
               remoteNode
             when /listed/ # serve host-directory
               if ('/' + host).R.exist?
                 remoteNode
               else
                 deny
               end
             when /short/ # shortened URL
               cachedRedirect
             else # undefined type-tags
               deny
             end if env.has_key? 'HTTP_TYPE'
      return chronoDir if chronoDir?    # goto time-slice
      return fileResponse if node.file? # static data
      if localResource?
        # local node
        graphResponse localNodes
      else
        remoteNode
      end
    end

    def HEAD
     self.GET.do{| s, h, b|
       [ s, h, []]}
    end

    HeaderAcronyms = %w{cl id spf utc xsrf}
    InternalHeaders = %w{accept-encoding feedurl links path-info query-string rack.errors rack.hijack rack.hijack? rack.input rack.logger rack.multiprocess rack.multithread rack.run-once rack.url-scheme rack.version remote-addr request-method request-path request-uri response script-name server-name server-port server-protocol server-software track unicorn.socket upgrade-insecure-requests version via x-forwarded-for}

    def localResource?
      %w{l [::1] 127.0.0.1 localhost}.member? @r['SERVER_NAME']
    end

    Methods = %w{GET HEAD OPTIONS PUT POST}

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

    def HTTP.print_body body, mime
      case mime
      when /application\/json/
        puts ::JSON.pretty_generate ::JSON.parse body
      when /application\/x-www-form-urlencoded/
        q = HTTP.parseQs body
        message = q.delete "message"
        puts q
        puts ::JSON.pretty_generate ::JSON.parse message if message
      else
        puts body
      end
    rescue ::JSON::ParserError
      nil
    end

    def print_body
      @r['rack.input'].do{|i|
        HTTP.print_body i.read, @r['CONTENT_TYPE'] }
    end

    def HTTP.print_header header
      header.map{|k,v|
        puts [k,v].join "\t"}
    end

    def print_header
      HTTP.print_header env
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

    def trackPOST
      env[:deny] = true
      [202,{},[]]
    end

    def self.unmangle env
      head = {}
      env.map{|k,v|
        key = k.to_s.downcase.sub(/^http_/,'').split('_').map{|k|
          if HeaderAcronyms.member? k
            k = k.upcase
          else
            k[0] = k[0].upcase
          end
          k
        }.join '-'
        head[key] = v.to_s unless InternalHeaders.member?(key.downcase)}
      head
    end

  end
  include HTTP
end
