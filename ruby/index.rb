%w(URI POSIX HTTP).map{|l|require_relative l}
%w(Audio Calendar CSS Feed HTML Image JS Mail Markdown PDF Text Video Web).map{|f|require_relative 'Formats/'+f}
require_relative '../config/site.rb'
