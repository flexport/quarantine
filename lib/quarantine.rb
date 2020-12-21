require 'rspec/retry'
require 'quarantine/rspec_adapter'
require 'quarantine/test'
require 'quarantine/databases/base'
require 'quarantine/databases/dynamo_db'

module RSpec
  module Core
    class Example
      # The implementation of clear_exception in rspec-retry doesn't work
      # for examples that use `it_behaves_like`, so we implement our own version that
      # clear the exception field recursively.
      def clear_exception!
        @exception = nil
        example.clear_exception! if defined?(example)
      end
    end
  end
end

class Quarantine
  attr_reader :options
  attr_reader :quarantined_ids
  attr_reader :failed_tests
  attr_reader :flaky_tests
  attr_reader :duplicate_tests
  attr_reader :summary

  def self.bind_rspec
    RSpecAdapter.bind_rspec
  end

  def initialize(options)
    @options = options
    @quarantined_ids = []
    @failed_tests = []
    @flaky_tests = []
    @summary = { id: 'quarantine', quarantined_tests: [], flaky_tests: [], database_failures: [] }
  end

  def database
    database_options = options[:database].dup
    type = database_options.delete(:type)
    @database ||= case type
    when :dynamodb
      Quarantine::Databases::DynamoDB.new(database_options)
    else
      raise Quarantine::UnsupportedDatabaseError.new("Quarantine does not support database type: #{type.inspect}")
    end
  end

  # Scans the quarantine_list from the database and store their IDs in quarantined_ids
  def fetch_quarantine_list
    begin
      quarantine_list = database.scan(options[:list_table])
    rescue Quarantine::DatabaseError => e
      add_to_summary(:database_failures, "#{e&.cause&.class}: #{e&.cause&.message}")
      raise Quarantine::DatabaseError.new(
        <<~ERROR_MSG
          Failed to pull the quarantine list from #{options[:list_table]}
          because of #{e&.cause&.class}: #{e&.cause&.message}
        ERROR_MSG
      )
    end

    @quarantined_ids = quarantine_list.map{|q| q['id']}
  end

  # Based off the type, upload a list of tests to a particular database table
  def upload_tests(type)
    if type == :failed
      tests = failed_tests
      table_name = options[:failed_tests_table]
    elsif type == :flaky
      tests = flaky_tests
      table_name = options[:list_table]
    else
      raise Quarantine::UnknownUploadError.new(
        "Quarantine gem did not know how to handle #{type} upload of tests to dynamodb"
      )
    end

    return unless tests.length < 10 && tests.length > 0

    begin
      timestamp = Time.now.to_i / 1000 # Truncated millisecond from timestamp for reasons specific to Flexport
      database.batch_write_item(
        table_name,
        tests,
        {
          created_at: timestamp,
          updated_at: timestamp
        }
      )
    rescue Quarantine::DatabaseError => e
      add_to_summary(:database_failures, "#{e&.cause&.class}: #{e&.cause&.message}")
    end
  end

  def create_test(example)
    extra_attributes = if options[:extra_attributes]
      options[:extra_attributes].call(example)
    else
      {}
    end
    Quarantine::Test.new(example.id, example.full_description, example.location, extra_attributes)
  end

  # Param: RSpec::Core::Example
  # Add the example to the internal failed tests list
  def record_failed_test(example)
    failed_tests << create_test(example)
  end

  # Param: RSpec::Core::Example
  # Add the example to the internal flaky tests list
  def record_flaky_test(example)
    flaky_test = create_test(example)

    flaky_tests << flaky_test
    add_to_summary(:flaky_tests, flaky_test.id)
  end

  # Param: RSpec::Core::Example
  # Clear exceptions on a flaky tests that has been quarantined
  def pass_flaky_test(example)
    example.clear_exception!
    add_to_summary(:quarantined_tests, example.id)
  end

  # Param: RSpec::Core::Example
  # Check the internal quarantined_ids to see if this test should be quarantined
  def test_quarantined?(example)
    quarantined_ids.include?(example.id)
  end

  # Param: Symbol, Any
  # Adds the item to the specified attribute in summary
  def add_to_summary(attribute, item)
    summary[attribute] << item if summary.key?(attribute)
  end
end
