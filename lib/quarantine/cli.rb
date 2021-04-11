# typed: strict

require 'optparse'
require_relative 'databases/base'
require_relative 'databases/dynamo_db'

class Quarantine
  class CLI
    extend T::Sig

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :options

    sig { void }
    def initialize
      # default options
      @options = T.let(
        {
          test_statuses_table_name: 'test_statuses'
        }, T::Hash[Symbol, T.untyped]
      )
    end

    sig { void }
    def parse
      OptionParser.new do |parser|
        parser.banner = 'Usage: quarantine_dynamodb [options]'

        parser.on('-rREGION', '--region=REGION', String, 'Specify the aws region for DynamoDB') do |region|
          @options[:region] = region
        end

        parser.on(
          '-qTABLE',
          '--quarantine_table=TABLE',
          String,
          "Specify the table name for the quarantine list | Default: #{@options[:test_statuses_table_name]}"
        ) do |table_name|
          @options[:test_statuses_table_name] = table_name
        end

        parser.on('-h', '--help', 'Prints help page') do
          puts parser # rubocop:disable Rails/Output
          exit
        end
      end.parse!

      if @options[:region].nil?
        error_msg = 'Failed to specify the required aws region with -r option'.freeze
        warn error_msg
        raise ArgumentError.new(error_msg)
      end
    end

    # TODO: eventually move to a separate file & create_table by db type when my db adapters
    sig { void }
    def create_tables
      dynamodb = Quarantine::Databases::DynamoDB.new(region: @options[:region])

      attributes = [
        { attribute_name: 'id', attribute_type: 'S', key_type: 'HASH' }
      ]

      additional_arguments = {
        provisioned_throughput: {
          read_capacity_units: 10,
          write_capacity_units: 5
        }
      }

      begin
        dynamodb.create_table(@options[:test_statuses_table_name], attributes, additional_arguments)
      rescue Quarantine::DatabaseError => e
        warn "#{e.cause&.class}: #{e.cause&.message}"
      end
    end
  end
end
