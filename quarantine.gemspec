# TEAM: backend_infra
#
$LOAD_PATH.push(File.expand_path('lib', __dir__))

# Maintain your gem's version:
require 'quarantine/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name = 'quarantine'
  s.version = Quarantine::VERSION
  s.authors = ['Flexport Engineering, Eric Zhu']
  s.email = ['ericzhu77@gmail.com']
  s.summary = 'Quarantine flaky Ruby Rspec tests'
  s.homepage = 'https://github.com/flexport/quarantine'
  s.license = 'MIT'
  s.files = Dir['{lib, bin}/**/*', '*.md', '*.gemspec']
  s.executables = ['quarantine_dynamodb']

  s.add_dependency('aws-sdk', '~> 2.11.41')
  s.add_dependency('rspec', '>= 3.0', '<= 4.0')
  s.add_dependency('rspec-retry', '~> 0.6.1')
end
