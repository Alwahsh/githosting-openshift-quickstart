require 'yaml'

require File.expand_path('../lib/gitserver', __FILE__)

ENV['OPENSHIFT_DIY_IP'] ||= '127.0.0.1'
ENV['OPENSHIFT_DIY_PORT'] ||= '8080'
ENV['OPENSHIFT_DATA_DIR'] ||= './tmp'

server = GitServer.new(YAML.load_file('config.yml'))
server.start