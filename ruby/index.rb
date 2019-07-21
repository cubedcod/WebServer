%w(URI POSIX HTTP).map{|component|
       require_relative component}

%w(Audio Calendar CSS Feed HTML Image JS Mail Markdown PDF Text Video Web).map{|format|
                                                  require_relative 'Formats/' + format}
require_relative '../config/site.rb'
