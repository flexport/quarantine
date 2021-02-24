class Quarantine
  module RSpecAdapter
    # Purpose: create an instance of Quarantine which contains information
    #          about the test suite (ie. quarantined tests) and binds RSpec configurations
    #          and hooks onto the global RSpec class
    def self.bind_rspec
      bind_rspec_configurations
      bind_quarantine_list
      bind_quarantine_checker
      bind_quarantine_record_tests
      bind_logger
    end

    def self.quarantine
      @quarantine ||= Quarantine.new(
        database: RSpec.configuration.quarantine_database,
        list_table: RSpec.configuration.quarantine_list_table,
        failed_tests_table: RSpec.configuration.quarantine_failed_tests_table
      )
    end

    # Purpose: binds rspec configuration variables
    def self.bind_rspec_configurations
      ::RSpec.configure do |config|
        config.add_setting(:quarantine_database, default: { type: :dynamodb, region: 'us-west-1' })
        config.add_setting(:quarantine_list_table, { default: 'quarantine_list' })
        config.add_setting(:quarantine_failed_tests_table, { default: 'master_failed_tests' })
        config.add_setting(:skip_quarantined_tests, { default: true })
        config.add_setting(:quarantine_record_failed_tests, { default: true })
        config.add_setting(:quarantine_record_flaky_tests, { default: true })
        config.add_setting(:quarantine_logging, { default: true })
        config.add_setting(:quarantine_extra_attributes)
      end
    end

    # Purpose: binds quarantine to fetch the quarantine_list from dynamodb in the before suite
    def self.bind_quarantine_list
      ::RSpec.configure do |config|
        config.before(:suite) do
          Quarantine::RSpecAdapter.quarantine.fetch_quarantine_list
        end
      end
    end

    # Purpose: binds quarantine to skip and pass tests that have been quarantined in the after suite
    def self.bind_quarantine_checker
      ::RSpec.configure do |config|
        config.after(:each) do |example|
          if RSpec.configuration.skip_quarantined_tests \
            && Quarantine::RSpecAdapter.quarantine.test_quarantined?(example)
            Quarantine::RSpecAdapter.quarantine.pass_flaky_test(example)
          end
        end
      end
    end

    # Purpose: binds quarantine to record failed and flaky tests
    def self.bind_quarantine_record_tests
      ::RSpec.configure do |config|
        config.after(:each) do |example|
          metadata = example.metadata

          # will record the failed test if is not quarantined and it is on it's final retry from the rspec-retry gem
          Quarantine::RSpecAdapter.quarantine.record_failed_test(example) if
            RSpec.configuration.quarantine_record_failed_tests &&
            !Quarantine::RSpecAdapter.quarantine.test_quarantined?(example) &&
            metadata[:retry_attempts] + 1 == metadata[:retry] && example.exception

          # will record the flaky test if is not quarantined and it failed the first run but passed a subsequent run;
          # optionally, the upstream RSpec configuration could define an after hook that marks an example as flaky in
          # the example's metadata
          Quarantine::RSpecAdapter.quarantine.record_flaky_test(example) if
            RSpec.configuration.quarantine_record_flaky_tests &&
            !Quarantine::RSpecAdapter.quarantine.test_quarantined?(example) &&
            (metadata[:retry_attempts] > 0 && example.exception.nil?) || metadata[:flaky]
        end
      end

      ::RSpec.configure do |config|
        config.after(:suite) do
          if RSpec.configuration.quarantine_record_failed_tests
            Quarantine::RSpecAdapter.quarantine.upload_tests(:failed)
          end

          Quarantine::RSpecAdapter.quarantine.upload_tests(:flaky) if RSpec.configuration.quarantine_record_flaky_tests
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
end
