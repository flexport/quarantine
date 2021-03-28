module Quarantine::RSpecAdapter # rubocop:disable Style/ClassAndModuleChildren
  # Purpose: create an instance of Quarantine which contains information
  #          about the test suite (ie. quarantined tests) and binds RSpec configurations
  #          and hooks onto the global RSpec class
  def self.bind_rspec
    bind_rspec_configurations
    bind_fetch_test_statuses
    bind_record_tests
    bind_upload_tests
    bind_logger
  end

  def self.quarantine
    @quarantine ||= Quarantine.new(
      database: RSpec.configuration.quarantine_database,
      test_statuses_table_name: RSpec.configuration.quarantine_test_statuses,
      extra_attributes: RSpec.configuration.quarantine_extra_attributes
    )
  end

  # Purpose: binds rspec configuration variables
  def self.bind_rspec_configurations
    ::RSpec.configure do |config|
      config.add_setting(:quarantine_database, default: { type: :dynamodb, region: 'us-west-1' })
      config.add_setting(:quarantine_test_statuses, { default: 'test_statuses' })
      config.add_setting(:skip_quarantined_tests, { default: true })
      config.add_setting(:quarantine_record_tests, { default: true })
      config.add_setting(:quarantine_logging, { default: true })
      config.add_setting(:quarantine_extra_attributes)
    end
  end

  # Purpose: binds quarantine to fetch the test_statuses from dynamodb in the before suite
  def self.bind_fetch_test_statuses
    ::RSpec.configure do |config|
      config.before(:suite) do
        Quarantine::RSpecAdapter.quarantine.fetch_test_statuses
      end
    end
  end

  # Purpose: binds quarantine to record test statuses
  def self.bind_record_tests
    ::RSpec.configure do |config|
      config.after(:each) do |example|
        metadata = example.metadata

        status = :passing
        if RSpec.configuration.skip_quarantined_tests && Quarantine::RSpecAdapter.quarantine.test_quarantined?(example)
          Quarantine::RSpecAdapter.quarantine.pass_flaky_test(example)
          status = :quarantined
        elsif metadata[:retry_attempts] + 1 == metadata[:retry] && example.exception
          # will record the failed test if it's final retry from the rspec-retry gem
          status = :failing
        elsif (metadata[:retry_attempts] > 0 && example.exception.nil?) || metadata[:flaky]
          # will record the flaky test if it failed the first run but passed a subsequent run;
          # optionally, the upstream RSpec configuration could define an after hook that marks an example as flaky in
          # the example's metadata
          status = :quarantined
        end

        Quarantine::RSpecAdapter.quarantine.record_test(example, status)
      end
    end
  end

  def self.bind_upload_tests
    ::RSpec.configure do |config|
      config.after(:suite) do
        Quarantine::RSpecAdapter.quarantine.upload_tests if RSpec.configuration.quarantine_record_tests
      end
    end
  end

  # Purpose: binds quarantine logger to output test to RSpec formatter messages
  def self.bind_logger
    ::RSpec.configure do |config|
      config.after(:suite) do
        if RSpec.configuration.quarantine_logging
          RSpec.configuration.reporter.message(Quarantine::RSpecAdapter.quarantine.summary)
        end
      end
    end
  end
end
