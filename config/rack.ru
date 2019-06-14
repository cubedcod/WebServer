require_relative '../ruby/index'
use Rack::CommonLogger, Logger.new('log/rack.log')
use Rack::Lint
run WebResource::HTTP
