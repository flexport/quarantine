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

    sig { params(example: RSpec::Core::Example).returns(T.nilable([Symbol, T::Boolean])) }
    def self.final_status(example)
      metadata = example.metadata

      # The user may define their own after hook that marks an example as flaky in its metadata.
      previously_quarantined = Quarantine::RSpecAdapter.quarantine.test_quarantined?(example) || metadata[:flaky]

      if example.exception
        # The example failed _this try_.
        if metadata[:retry_attempts] + 1 == metadata[:retry]
          # The example failed all its retries - if it's already quarantined, keep it that way;
          # otherwise, mark it as failing.
          if RSpec.configuration.skip_quarantined_tests && previously_quarantined
            return [:quarantined, false]
          else
            return [:failing, false]
          end
        end
        # The example failed, but it's not the final retry yet, so return nil.
        return nil # rubocop:disable Style/RedundantReturn
      elsif metadata[:retry_attempts] > 0
        # The example passed this time, but failed one or more times before - the definition of a flaky test.
        return [:quarantined, false] # rubocop:disable Style/RedundantReturn
      elsif previously_quarantined
        # The example passed the first time, but it's already marked quarantined, so keep it that way.
        return [:quarantined, true] # rubocop:disable Style/RedundantReturn
      else
        return [:passing, true] # rubocop:disable Style/RedundantReturn
      end
    end

    # Purpose: binds quarantine to record test statuses
    sig { void }
    def self.bind_on_test
      ::RSpec.configure do |config|
        config.after(:each) do |example|
          result = Quarantine::RSpecAdapter.final_status(example)
          if result
            status, passed = result
            example.clear_exception! if status == :quarantined && !passed
            Quarantine::RSpecAdapter.quarantine.on_test(example, status, passed: passed)
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
