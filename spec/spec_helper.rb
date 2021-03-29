# typed: strict
require 'quarantine'
require 'rspec/retry'

RSpec.configure do |config|
  config.add_setting(:quarantine_list_table, { default: 'quarantine_list' })
  config.add_setting(:quarantine_failed_tests_table, { default: 'master_failed_tests' })
  config.add_setting(:skip_quarantined_tests, { default: true })
  config.add_setting(:quarantine_record_failed_tests, { default: true })
  config.add_setting(:quarantine_record_flaky_tests, { default: true })
  config.add_setting(:remove_duplicate_tests, { default: true })
  config.add_setting(:quarantine_logging, { default: true })
end
