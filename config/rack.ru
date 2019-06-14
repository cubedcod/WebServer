require_relative '../ruby/index'
#use Rack::CommonLogger, Logger.new('log/rack.log')
run WebResource::HTTP
