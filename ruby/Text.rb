# coding: utf-8
class WebResource
  module POSIX

    # grepPattern -> file(s)
    def grep q
      env[:grep] = true
      args = POSIX.splitArgs q
      case args.size
      when 0
        return []
      when 2 # two unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -il #{args[1].sh}"
      when 3 # three unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -il #{args[2].sh}"
      when 4 # four unordered terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -ilZ #{args[2].sh} | xargs -0 grep -il #{args[3].sh}"
      else # N ordered terms
        pattern = args.join '.*'
        cmd = "grep -ril #{pattern.sh} #{sh}"
      end
      `#{cmd} | head -n 1024`.lines.map{|path|
        POSIX.fromRelativePath path.chomp}
    end

  end
  module HTML

    def htmlGrep graph, q
      wordIndex = {}
      args = POSIX.splitArgs q
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      pattern = /(#{args.join '|'})/i

      # find matches
      graph.map{|k,v|
        graph.delete k unless (k.to_s.match pattern) || (v.to_s.match pattern)}

      # highlight matches in exerpt
      graph.values.map{|r|
        (r[Content]||r[Abstract]).justArray.map{|v|v.respond_to?(:lines) ? v.lines : nil}.flatten.compact.grep(pattern).do{|lines|
          r[Abstract] = lines[0..5].map{|l|
            l.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # matches
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g}) # wrap in styled node
            }} if lines.size > 0 }}

      # CSS
      graph['#abstracts'] = {Abstract => HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})}
    end

  end
  module Webize

    BasicSlugs = %w{
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r reddit rss rssfeed
 sports source story
 t the threads topic tumblr
 uk utm www}

    def triplrText enc=nil, &f
      doc = stripDoc.uri
      mtime.do{|mt|
        yield doc, Date, mt.iso8601}
      yield doc, Content,
            HTML.render({_: :pre,
                         style: 'white-space: pre-wrap',
                         c: readFile.do{|r|
                           enc ? r.force_encoding(enc).to_utf8 : r}.
                           hrefs{|p,o| # hypertextize
                           # yield detected links to consumer
                           yield doc, p, o
                           yield o.uri, Type, Resource.R
                         }})
    end

    def triplrMarkdown
      doc = stripDoc.uri
      yield doc, Content, ::Redcarpet::Markdown.new(::Redcarpet::Render::Pygment, fenced_code_blocks: true).render(readFile)
      mtime.do{|mt|yield doc, Date, mt.iso8601}
    end

    def triplrCSV d
      ns    = W3 + 'ns/csv#'
      lines = CSV.read localPath
      lines[0].do{|fields| # header-row
        yield uri, Type, (ns+'Table').R
        yield uri, ns+'rowCount', lines.size
        lines[1..-1].each_with_index{|row,line|
          row.each_with_index{|field,i|
            id = uri + '#row:' + line.to_s
            yield id, fields[i], field
            yield id, Type, (ns+'Row').R}}}
    end
  end
end

class String
  def sha2; Digest::SHA2.hexdigest self end
  def to_utf8; encode('UTF-8', undef: :replace, invalid: :replace, replace: '?') end
end
