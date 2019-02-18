# coding: utf-8
class WebResource
  module POSIX
    # grepPattern -> file(s)
    def grep q
      args = POSIX.splitArgs q
      case args.size
      when 0
        return []
      when 2 # two terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -il #{args[1].sh}"
      when 3 # three terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -il #{args[2].sh}"
      when 4 # four terms
        cmd = "grep -rilZ #{args[0].sh} #{sh} | xargs -0 grep -ilZ #{args[1].sh} | xargs -0 grep -ilZ #{args[2].sh} | xargs -0 grep -il #{args[3].sh}"
      else # N terms in sequential order of appearance in match in one process invocation (if anyone reaches this, maybe theyre pasting in a sentence in which case the args are ordered)
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
      # tokenize
      args = POSIX.splitArgs q
      args.each_with_index{|arg,i| wordIndex[arg] = i }
      # highlight any matches via OR pattern
      pattern = /(#{args.join '|'})/i

      # find matches
      graph.map{|k,v|
        graph.delete k unless (k.match pattern) || (v.to_s.match pattern)}

      # highlighted matches in Abstract field
      graph.values.map{|r|
        (r[Content]||r[Abstract]).justArray.map(&:lines).flatten.grep(pattern).do{|lines|
          r[Abstract] = lines[0..5].map{|l|
            l.gsub(/<[^>]+>/,'')[0..512].gsub(pattern){|g| # capture
              HTML.render({_: :span, class: "w#{wordIndex[g.downcase]}", c: g}) # wrap
            }} if lines.size > 0 }}

      # CSS
      graph['#abstracts'] = {Abstract => HTML.render({_: :style, c: wordIndex.values.map{|i|
                                                        ".w#{i} {background-color: #{'#%06x' % (rand 16777216)}; color: white}\n"}})}
    end
  end
  module Webize
    def triplrArchive &f;     yield uri, Type, (Stat+'Archive').R; triplrFile &f end
    def triplrAudio &f;       yield uri, Type, Sound.R; triplrFile &f end
    def triplrDataFile &f;    yield uri, Type, (Stat+'DataFile').R; triplrFile &f end

    def triplrBat &f
      yield uri, Content, `pygmentize -l batch -f html #{sh}` end
    def triplrDocker &f
      yield uri, Content, `pygmentize -l docker -f html #{sh}` end
    def triplrIni &f
      yield uri, Content, `pygmentize -l ini -f html #{sh}` end
    def triplrMakefile &f
      yield uri, Content, `pygmentize -l make -f html #{sh}` end
    def triplrLisp &f
      yield uri, Content, `pygmentize -l lisp -f html #{sh}` end
    def triplrShellScript &f
      yield uri, Content, `pygmentize -l sh -f html #{sh}` end
    def triplrRuby &f
      yield uri, Content, `pygmentize -l ruby -f html #{sh}` end
    def triplrCode &f # pygments determines type
      yield uri, Content, `pygmentize -f html #{sh}`
    end

    def triplrWord conv, argB='', &f
      yield uri, Content, '<pre>' + `#{conv} #{sh} #{argB}` + '</pre>'
      triplrFile &f
    end

    def triplrRTF          &f; triplrWord :catdoc,        &f end
    def triplrWordDoc      &f; triplrWord :antiword,      &f end
    def triplrWordXML      &f; triplrWord :docx2txt, '-', &f end
    def triplrOpenDocument &f; triplrWord :odt2txt,       &f end

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
    
    def triplrTeX
      yield stripDoc.uri, Content, `cat #{sh} | tth -r` end

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
