require_relative '../ruby/index'
use Rack::Deflater
run WebResource::HTTP
