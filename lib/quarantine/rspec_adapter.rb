module RSpecAdapter
  # Purpose: create an instance of Quarantine which contains information
  #          about the test suite (ie. quarantined tests) and binds RSpec configurations
  #          and hooks onto the global RSpec class
  def bind(options = {})
    quarantine = Quarantine.new(options)
    bind_rspec_configurations
    bind_quarantine_list(quarantine)
    bind_quarantine_checker(quarantine)
    bind_quarantine_record_tests(quarantine)
    bind_logger(quarantine)
  end

  private

  # Purpose: binds rspec configuration variables
  def bind_rspec_configurations
    ::RSpec.configure do |config|
      config.add_setting(:quarantine_list_table, { default: 'quarantine_list' })
      config.add_setting(:quarantine_failed_tests_table, { default: 'master_failed_tests' })
      config.add_setting(:skip_quarantined_tests, { default: true })
      config.add_setting(:quarantine_record_failed_tests, { default: true })
      config.add_setting(:quarantine_record_flaky_tests, { default: true })
      config.add_setting(:quarantine_logging, { default: true })
    end
  end

  # Purpose: binds quarantine to fetch the quarantine_list from dynamodb in the before suite
  def bind_quarantine_list(quarantine)
    ::RSpec.configure do |config|
      config.before(:suite) do
        quarantine.fetch_quarantine_list
      end
    end
  end

  # Purpose: binds quarantine to skip and pass tests that have been quarantined in the after suite
  def bind_quarantine_checker(quarantine)
    ::RSpec.configure do |config|
      config.after(:each) do |example|
        if RSpec.configuration.skip_quarantined_tests && quarantine.test_quarantined?(example)
          quarantine.pass_flaky_test(example)
        end
      end
    end
  end

  # Purpose: binds quarantine to record failed and flaky tests
  def bind_quarantine_record_tests(quarantine)
    ::RSpec.configure do |config|
      config.after(:each) do |example|
        metadata = example.metadata

        # will record the failed test if is not quarantined and it is on it's final retry from the rspec-retry gem
        quarantine.record_failed_test(example) if
          RSpec.configuration.quarantine_record_failed_tests &&
          !quarantine.test_quarantined?(example) &&
          metadata[:retry_attempts] + 1 == metadata[:retry] && example.exception

        # will record the flaky test if is not quarantined and it failed the first run but passed a subsequent run;
        # optionally, the upstream RSpec configuration could define an after hook that marks an example as flaky in
        # the example's metadata
        quarantine.record_flaky_test(example) if
          RSpec.configuration.quarantine_record_flaky_tests &&
          !quarantine.test_quarantined?(example) &&
          (metadata[:retry_attempts] > 0 && example.exception.nil?) || metadata[:flaky]
      end
    end

    ::RSpec.configure do |config|
      config.after(:suite) do
        quarantine.upload_tests(:failed) if RSpec.configuration.quarantine_record_failed_tests

        quarantine.upload_tests(:flaky) if RSpec.configuration.quarantine_record_flaky_tests
      end
    end
  end

  # Purpose: binds quarantine logger to output test to RSpec formatter messages
  def bind_logger(quarantine)
    ::RSpec.configure do |config|
      config.after(:suite) do
        RSpec.configuration.reporter.message(quarantine.summary) if RSpec.configuration.quarantine_logging
      end
    end
  end
end
