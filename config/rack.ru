require 'resolv'
require 'resolv-replace'
hosts_resolver = Resolv::Hosts.new('/etc/hosts')
dns_resolver = Resolv::DNS.new nameserver: %w(1.1.1.1 8.8.8.8)
Resolv::DefaultResolver.replace_resolvers([hosts_resolver, dns_resolver])

require_relative '../index'
run WebResource::HTTP
