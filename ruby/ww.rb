# deps
%w{cgi csv date digest/sha2 dimensions fileutils httparty icalendar json linkeddata mail nokogiri open-uri pathname rack rdf redcarpet shellwords}.map{|r|require r}

# this
%w{URI MIME HTML HTTP POSIX Graph Feed Image Msg Proxy Text}.map{|i|require_relative i}

# stdlib additions TODO remove, &. syntax and minor rewrites can facilitate #do replacement
class Array
  def head; self[0] end
  def justArray; self end
  def intersperse i; inject([]){|a,b|a << b << i}[0..-2] end
end
class Object
  def justArray; [self] end
  def do; yield self end # non-nil/false args ->run block
  def to_time; [Time, DateTime].member?(self.class) ? self : Time.parse(self) end
end
class FalseClass
  def do; self end # no arg exists for block, just yield false/nil
end
class NilClass
  def justArray; [] end
  def do; self end
end
