# typed: strict

module RSpec
  module Core
    class Example
      extend T::Sig

      # The implementation of clear_exception in rspec-retry doesn't work
      # for examples that use `it_behaves_like`, so we implement our own version that
      # clear the exception field recursively.
      sig { void }
      def clear_exception!
        @exception = T.let(nil, T.untyped)
        T.unsafe(self).example.clear_exception! if defined?(example)
      end
    end
  end
end

class Quarantine
  module RSpecAdapter
    extend T::Sig

    sig { void }
    def self.bind
      register_rspec_configurations
      bind_on_start
      bind_on_test
      bind_on_complete
    end

    sig { returns(Quarantine) }
    def self.quarantine
      @quarantine = T.let(@quarantine, T.nilable(Quarantine))
      @quarantine ||= Quarantine.new(
        database: RSpec.configuration.quarantine_database,
        test_statuses_table_name: RSpec.configuration.quarantine_test_statuses,
        extra_attributes: RSpec.configuration.quarantine_extra_attributes,
        failsafe_limit: RSpec.configuration.quarantine_failsafe_limit,
        release_at_consecutive_passes: RSpec.configuration.quarantine_release_at_consecutive_passes,
        logging: RSpec.configuration.quarantine_logging,
        log: method(:log),
        record_tests: RSpec.configuration.quarantine_record_tests
      )
    end

    # Purpose: binds rspec configuration variables
    sig { void }
    def self.register_rspec_configurations
      ::RSpec.configure do |config|
        config.add_setting(:quarantine_database, default: { type: :dynamodb, region: 'us-west-1' })
        config.add_setting(:quarantine_test_statuses, { default: 'test_statuses' })
        config.add_setting(:skip_quarantined_tests, { default: true })
        config.add_setting(:quarantine_record_tests, { default: true })
        config.add_setting(:quarantine_logging, { default: true })
        config.add_setting(:quarantine_extra_attributes)
        config.add_setting(:quarantine_failsafe_limit, default: 10)
        config.add_setting(:quarantine_release_at_consecutive_passes)
      end
    end

    # Purpose: binds quarantine to fetch the test_statuses from dynamodb in the before suite
    sig { void }
    def self.bind_on_start
      ::RSpec.configure do |config|
        config.before(:suite) do
          Quarantine::RSpecAdapter.quarantine.on_start
        end
      end
    end

    # Purpose: binds quarantine to record test statuses
    sig { void }
    def self.bind_on_test
      ::RSpec.configure do |config|
        config.after(:each) do |example|
          metadata = example.metadata

          # optionally, the upstream RSpec configuration could define an after hook that marks an example as flaky in
          # the example's metadata
          quarantined = Quarantine::RSpecAdapter.quarantine.test_quarantined?(example) || metadata[:flaky]
          if example.exception
            if metadata[:retry_attempts] + 1 == metadata[:retry]
              # will record the failed test if it's final retry from the rspec-retry gem
              if RSpec.configuration.skip_quarantined_tests && quarantined
                example.clear_exception!
                Quarantine::RSpecAdapter.quarantine.on_test(example, :quarantined, passed: false)
              else
                Quarantine::RSpecAdapter.quarantine.on_test(example, :failing, passed: false)
              end
            end
          elsif metadata[:retry_attempts] > 0
            # will record the flaky test if it failed the first run but passed a subsequent run
            Quarantine::RSpecAdapter.quarantine.on_test(example, :quarantined, passed: false)
          elsif quarantined
            Quarantine::RSpecAdapter.quarantine.on_test(example, :quarantined, passed: true)
          else
            Quarantine::RSpecAdapter.quarantine.on_test(example, :passing, passed: true)
          end
        end
      end
    end

    sig { void }
    def self.bind_on_complete
      ::RSpec.configure do |config|
        config.after(:suite) do
          Quarantine::RSpecAdapter.quarantine.on_complete
        end
      end
    end

    sig { params(message: String).void }
    def self.log(message)
      RSpec.configuration.reporter.message(message)
    end
  end
end
