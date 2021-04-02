# typed: strict

require 'sorbet-runtime'

require 'rspec/retry'
require 'quarantine/rspec_adapter'
require 'quarantine/test'
require 'quarantine/databases/base'
require 'quarantine/databases/dynamo_db'

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
  extend T::Sig

  sig { void }
  def self.bind_rspec
    RSpecAdapter.bind_rspec
  end

  sig { returns(T::Hash[String, Quarantine::Test]) }
  attr_reader :tests

  sig { returns(T::Hash[String, Quarantine::Test]) }
  attr_reader :old_tests

  sig { params(options: T::Hash[T.untyped, T.untyped]).void }
  def initialize(options)
    @options = options
    @old_tests = T.let({}, T::Hash[String, Quarantine::Test])
    @tests = T.let({}, T::Hash[String, Quarantine::Test])
    @database_failures = T.let([], T::Array[String])
    @database = T.let(nil, T.nilable(Quarantine::Databases::Base))
  end

  sig { returns(Quarantine::Databases::Base) }
  def database
    database_options = @options[:database].dup
    type = database_options.delete(:type)
    @database ||= \
      case type
      when :dynamodb
        Quarantine::Databases::DynamoDB.new(database_options)
      else
        raise Quarantine::UnsupportedDatabaseError.new("Quarantine does not support database type: #{type.inspect}")
      end
  end

  # Scans the test_statuses from the database and store their IDs in quarantined_ids
  sig { void }
  def fetch_test_statuses
    begin
      test_statuses = database.scan(@options[:test_statuses_table_name])
    rescue Quarantine::DatabaseError => e
      @database_failures << "#{e.cause&.class}: #{e.cause&.message}"
      raise Quarantine::DatabaseError.new(
        <<~ERROR_MSG
          Failed to pull the quarantine list from #{@options[:test_statuses_table_name]}
          because of #{e.cause&.class}: #{e.cause&.message}
        ERROR_MSG
      )
    end

    pairs =
      test_statuses
      .group_by { |t| t['id'] }
      .map { |_id, tests| tests.max_by { |t| t['created_at'] } }
      .compact
      .filter { |t| t['last_status'] == 'quarantined' }
      .map do |t|
        [
          t['id'],
          Quarantine::Test.new(
            id: t['id'],
            status: t['last_status'].to_sym,
            consecutive_passes: t['consecutive_passes'],
            full_description: t['full_description'],
            location: t['location'],
            extra_attributes: t['extra_attributes']
          )
        ]
      end

    @old_tests = Hash[pairs]
  end

  sig { void }
  def upload_tests
    return if @tests.empty? || @tests.values.count { |test| test.status == :quarantined } >= @options[:failsafe_limit]

    begin
      timestamp = Time.now.to_i / 1000 # Truncated millisecond from timestamp for reasons specific to Flexport
      database.batch_write_item(
        @options[:test_statuses_table_name],
        @tests.values.map(&:to_hash),
        {
          updated_at: timestamp
        }
      )
    rescue Quarantine::DatabaseError => e
      @database_failures << "#{e.cause&.class}: #{e.cause&.message}"
    end
  end

  # Param: RSpec::Core::Example
  # Add the example to the internal tests list
  sig { params(example: T.untyped, status: Symbol, passed: T::Boolean).void }
  def record_test(example, status, passed:)
    extra_attributes = @options[:extra_attributes] ? @options[:extra_attributes].call(example) : {}

    new_consecutive_passes = passed ? (@old_tests[example.id]&.consecutive_passes || 0) + 1 : 0
    release_at = @options[:release_at_consecutive_passes]
    new_status = !release_at.nil? && new_consecutive_passes >= release_at ? :passing : status
    test = Quarantine::Test.new(
      id: example.id,
      status: new_status,
      consecutive_passes: new_consecutive_passes,
      full_description: example.full_description,
      location: example.location,
      extra_attributes: extra_attributes
    )

    @tests[test.id] = test
  end

  # Param: RSpec::Core::Example
  # Check the internal old_tests to see if this test should be quarantined
  sig { params(example: T.untyped).returns(T::Boolean) }
  def test_quarantined?(example)
    @old_tests[example.id]&.status == :quarantined
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def summary
    {
      id: 'quarantine',
      tests: @tests.transform_values(&:status),
      database_failures: @database_failures
    }
  end
end
