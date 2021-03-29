# typed: false
require 'spec_helper'
require_relative '../../lib/quarantine/cli'

describe Quarantine::CLI do
  context '#initialize' do
    it 'options are set with their default value' do
      cli = Quarantine::CLI.new

      expect(cli.options[:test_statuses_table_name]).to eq('test_statuses')
    end
  end

  context '#parse' do
    it 'throws exception if an aws region is not defined' do
      cli = Quarantine::CLI.new

      expect { cli.parse }.to raise_error(ArgumentError)
    end

    it 'defined aws region in arguments' do
      cli = Quarantine::CLI.new

      ARGV << '-r' << 'us-west-1'
      cli.parse

      expect(cli.options[:region]).to eq('us-west-1')
    end

    it 'define test statuses table name' do
      cli = Quarantine::CLI.new

      ARGV << '-r' << 'us-west-1'
      ARGV << '-q' << 'foo'
      cli.parse

      expect(cli.options[:test_statuses_table_name]).to eq('foo')
    end

    context '#create_tables' do
      let(:dynamodb) { Quarantine::Databases::DynamoDB.new(region: 'us-west-1') }
      let(:cli) { Quarantine::CLI.new }

      it 'called with the correct arguments' do
        attributes = [
          { attribute_name: 'id', attribute_type: 'S', key_type: 'HASH' }
        ]

        additional_arguments = {
          provisioned_throughput: {
            read_capacity_units: 10,
            write_capacity_units: 5
          }
        }

        allow(Quarantine::Databases::DynamoDB).to receive(:new).and_return(dynamodb)
        expect(dynamodb).to receive(:create_table).with(
          'test_statuses',
          attributes,
          additional_arguments
        ).once

        cli.create_tables
      end

      it 'raises exception if Quarantine::DatabaseError exception occurs' do
        allow(Quarantine::Databases::DynamoDB).to receive(:new).and_return(dynamodb)
        allow(dynamodb).to receive(:create_table).and_raise(Quarantine::DatabaseError.new('db error'))

        expect { cli.create_tables }.to_not raise_error
      end
    end
  end
end
