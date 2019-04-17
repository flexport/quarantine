require 'aws-sdk'
require 'rspec/retry'
require 'quarantine/rspec_adapter'
require 'quarantine/test'
require 'quarantine/databases/base'
require 'quarantine/databases/dynamo_db'

class Quarantine
  extend RSpecAdapter

  attr_accessor :database
  attr_reader :quarantine_map
  attr_reader :failed_tests
  attr_reader :flaky_tests
  attr_reader :duplicate_tests
  attr_reader :buildkite_build_number
  attr_reader :summary

  def initialize(options = {})
    case options[:database]
    # default database option is dynamodb
    when :dynamodb, nil
      @database = Quarantine::Databases::DynamoDB.new(options)
    else
      raise Quarantine::UnsupportedDatabaseError.new("Quarantine does not support #{options[:database]}")
    end

    @quarantine_map = {}
    @failed_tests = []
    @flaky_tests = []
    @buildkite_build_number = ENV['BUILDKITE_BUILD_NUMBER'] || '-1'
    @summary = { id: 'quarantine', quarantined_tests: [], flaky_tests: [], database_failures: [] }
  end

  # Scans the quarantine_list from the database and store the individual tests in quarantine_map
  def fetch_quarantine_list
    begin
      quarantine_list = database.scan(RSpec.configuration.quarantine_list_table)
    rescue Quarantine::DatabaseError => e
      add_to_summary(:database_failures, "#{e&.cause&.class}: #{e&.cause&.message}")
      raise Quarantine::DatabaseError.new(
        <<~ERROR_MSG
          Failed to pull the quarantine list from #{RSpec.configuration.quarantine_list_table}
          because of #{e&.cause&.class}: #{e&.cause&.message}
        ERROR_MSG
      )
    end

    quarantine_list.each do |example|
      # on the rare occassion there are duplicate tests ids in the quarantine_list,
      # quarantine the most recent instance of the test (det. through build_number)
      # and ignore the older instance of the test
      next if
        quarantine_map.key?(example['id']) &&
        example['build_number'].to_i < quarantine_map[example['id']].build_number.to_i

      quarantine_map.store(
        example['id'],
        Quarantine::Test.new(example['id'], example['full_description'], example['location'], example['build_number'])
      )
    end
  end

  # Based off the type, upload a list of tests to a particular database table
  def upload_tests(type)
    if type == :failed
      tests = failed_tests
      table_name = RSpec.configuration.quarantine_failed_tests_table
    elsif type == :flaky
      tests = flaky_tests
      table_name = RSpec.configuration.quarantine_list_table
    else
      raise Quarantine::UnknownUploadError.new(
        "Quarantine gem did not know how to handle #{type} upload of tests to dynamodb"
      )
    end

    return unless tests.length < 10 && tests.length > 0

    begin
      timestamp = Time.now.to_i / 1000
      database.batch_write_item(
        table_name,
        tests,
        {
          build_job_id: ENV['BUILDKITE_JOB_ID'] || '-1',
          created_at: timestamp,
          updated_at: timestamp
        }
      )
    rescue Quarantine::DatabaseError => e
      add_to_summary(:database_failures, "#{e&.cause&.class}: #{e&.cause&.message}")
    end
  end

  # Param: RSpec::Core::Example
  # Add the example to the internal failed tests list
  def record_failed_test(example)
    failed_tests << Quarantine::Test.new(
      example.id,
      example.full_description,
      example.location,
      buildkite_build_number
    )
  end

  # Param: RSpec::Core::Example
  # Add the example to the internal flaky tests list
  def record_flaky_test(example)
    flaky_test = Quarantine::Test.new(
      example.id,
      example.full_description,
      example.location,
      buildkite_build_number
    )

    flaky_tests << flaky_test
    add_to_summary(:flaky_tests, flaky_test)
  end

  # Param: RSpec::Core::Example
  # Clear exceptions on a flaky tests that has been quarantined
  #
  # example.clear_exception is tightly coupled with the rspec-retry gem and will only exist if
  # the rspec-retry gem is enabled
  def pass_flaky_test(example)
    example.clear_exception
    add_to_summary(:quarantined_tests, example.id)
  end

  # Param: RSpec::Core::Example
  # Check the internal quarantine_map to see if this test should be quarantined
  def test_quarantined?(example)
    quarantine_map.key?(example.id)
  end

  # Param: Symbol, Any
  # Adds the item to the specified attribute in summary
  def add_to_summary(attribute, item)
    summary[attribute] << item if summary.key?(attribute)
  end
end
