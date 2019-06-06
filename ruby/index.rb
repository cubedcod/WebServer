# depended libraries
%w{brotli cgi csv date digest/sha2 dimensions fileutils httparty icalendar json linkeddata mail nokogiri open-uri pathname protobuf rack rdf redcarpet shellwords}.map{|r|require r}
%w{URI MIME HTML HTTP POSIX Graph Feed Msg Text}.map{|i|require_relative i} # library components
require_relative '../config/site.rb' # site config
# bonus methods
class Array
  def head; self[0] end
  def justArray; self end
  def intersperse i; inject([]){|a,b|a << b << i}[0..-2] end
end
class Object
  def justArray; [self] end
  def do; yield self end
  def to_time; [Time, DateTime].member?(self.class) ? self : Time.parse(self) end
end
class FalseClass
  def do; self end
end
class NilClass
  def justArray; [] end
  def do; self end
end
