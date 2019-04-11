require 'optparse'
require_relative 'databases/base'
require_relative 'databases/dynamo_db'

class Quarantine
  class CLI
    attr_accessor :options

    def initialize
      # default options
      @options = {
        quarantine_list_table_name: 'quarantine_list',
        failed_test_table_name: 'master_failed_tests'
      }
    end

    def parse
      OptionParser.new do |parser|
        parser.banner = 'Usage: quarantine_dynamodb [options]'

        parser.on('-rREGION', '--aws_region=REGION', String, 'Specify the aws region for DynamoDB') do |aws_region|
          options[:aws_region] = aws_region
        end

        parser.on(
          '-qTABLE',
          '--quarantine_table=TABLE',
          String,
          "Specify the table name for the quarantine list | Default: #{options[:quarantine_list_table_name]}"
        ) do |table_name|
          options[:quarantine_list_table_name] = table_name
        end

        parser.on(
          '-fTABLE',
          '--failed_table=TABLE',
          String,
          "Specify the table name for the failed test list | Default: #{options[:failed_test_table_name]}"
        ) do |table_name|
          options[:failed_test_table_name] = table_name
        end

        parser.on('-h', '--help', 'Prints help page') do
          puts parser # rubocop:disable Rails/Output
          exit
        end
      end.parse!

      if options[:aws_region].nil?
        error_msg = 'Failed to specify the required aws region with -r option'.freeze
        warn error_msg
        raise ArgumentError.new(error_msg)
      end
    end

    # TODO: eventually move to a separate file & create_table by db type when my db adapters
    def create_tables
      dynamodb = Quarantine::Databases::DynamoDB.new(options)

      attributes = [
        { attribute_name: 'id', attribute_type: 'S', key_type: 'HASH' },
        { attribute_name: 'build_number', attribute_type: 'S', key_type: 'RANGE' }
      ]

      additional_arguments = {
        provisioned_throughput: {
          read_capacity_units: 10,
          write_capacity_units: 5
        }
      }

      begin
        dynamodb.create_table(options[:quarantine_list_table_name], attributes, additional_arguments)
      rescue Quarantine::DatabaseError => e
        warn "#{e&.cause&.class}: #{e&.cause&.message}"
      end

      begin
        dynamodb.create_table(options[:failed_test_table_name], attributes, additional_arguments)
      rescue Quarantine::DatabaseError => e
        warn "#{e&.cause&.class}: #{e&.cause&.message}"
      end
    end
  end
end
