# typed: false
require 'spec_helper'

describe Quarantine::Databases::DynamoDB do
  context '#scan' do
    test1 = {
      'full_description' => 'quarantined_test_1',
      'id' => '1',
      'location' => 'line 1',
      'extra_attributes' => { 'build_number' => '123' }
    }

    test2 = {
      'full_description' => 'quarantined_test_2',
      'id' => '2',
      'location' => 'line 2',
      'extra_attributes' => { 'build_number' => '-1' }
    }

    let(:dynamodb) { Aws::DynamoDB::Client.new(stub_responses: true) }
    let(:stub_multiple_tests) { dynamodb.stub_data(:scan, items: [test1, test2]) }
    let(:database) { Quarantine::Databases::DynamoDB.new(region: 'us-west-1') }

    before(:each) do
      database.dynamodb = dynamodb
    end

    it 'is called with the correct table name' do
      expect(database.dynamodb).to receive(:scan).with(table_name: 'foo').and_return(OpenStruct.new(items: [])).once
      database.scan('foo')
    end

    it 'returns all items queried in the scan' do
      database.dynamodb.stub_responses(:scan, stub_multiple_tests)
      items = database.scan('foo')

      expect(items.length).to eq(2)
      expect(items[0]['id']).to eq('1')
      expect(items[0]['full_description']).to eq('quarantined_test_1')
      expect(items[0]['location']).to eq('line 1')
      expect(items[0]['extra_attributes']).to eq('build_number' => '123')

      expect(items[1]['id']).to eq('2')
      expect(items[1]['full_description']).to eq('quarantined_test_2')
      expect(items[1]['location']).to eq('line 2')
      expect(items[1]['extra_attributes']).to eq('build_number' => '-1')
    end

    it 'throws exception Quarantine::DatabaseError on AWS errors' do
      error = Aws::DynamoDB::Errors::TableNotFoundException.new(Quarantine, 'table not found')
      expect(database.dynamodb).to receive(:scan).and_raise(error)
      expect { database.scan('foo') }.to raise_error(Quarantine::DatabaseError)
    end
  end

  context '#batch_write_item' do
    item1 = Quarantine::Test.new(
      id: '1',
      status: :quarantined,
      consecutive_passes: 1,
      full_description: 'quarantined_test_1',
      location: 'line 1',
      extra_attributes: { foo: '123' }
    )
    item2 = Quarantine::Test.new(
      id: '2',
      status: :quarantined,
      consecutive_passes: 1,
      full_description: 'quarantined_test_2',
      location: 'line 2',
      extra_attributes: { foo: '-1' }
    )

    let(:database) { Quarantine::Databases::DynamoDB.new(region: 'us-west-1', stub_responses: true) }
    let(:items) { [item1, item2] }
    let(:additional_attributes) { { a: 'a', b: 'b' } }

    it 'has arguments splatted correctly' do
      result = {
        request_items: {
          'foo' => [
            {
              put_request: {
                item: item1.to_hash.merge(additional_attributes)
              }
            },
            {
              put_request: {
                item: item2.to_hash.merge(additional_attributes)
              }
            }
          ]
        }
      }

      expect(database.dynamodb).to receive(:batch_write_item).with(result).once

      database.batch_write_item('foo', items, additional_attributes)
    end

    it 'throws exception Quarantine::DatabaseError on AWS errors' do
      items = [
        Quarantine::Test.new(
          id: 'some_id',
          status: :some_status,
          consecutive_passes: 1,
          full_description: 'some description',
          location: 'some location',
          extra_attributes: { build_number: 'some build_number' }
        )
      ]
      error = Aws::DynamoDB::Errors::LimitExceededException.new(Quarantine, 'limit exceeded')
      expect(database.dynamodb).to receive(:batch_write_item).and_raise(error)
      expect { database.batch_write_item('foo', items) }.to raise_error(Quarantine::DatabaseError)
    end
  end

  context '#delete_item' do
    let(:database) { Quarantine::Databases::DynamoDB.new(region: 'us-west-1') }

    it 'has arguments splatted correctly' do
      result = {
        table_name: 'foo',
        key: { id: '1' }
      }
      expect(database.dynamodb).to receive(:delete_item).with(result)

      database.delete_item('foo', id: '1')
    end

    it 'throws exception Quarantine::DatabaseError on AWS errors' do
      error = Aws::DynamoDB::Errors::IndexNotFoundException.new(Quarantine, 'index not found')
      expect(database.dynamodb).to receive(:delete_item).and_raise(error)
      expect { database.delete_item('foo', id: '1') }.to raise_error(Quarantine::DatabaseError)
    end
  end

  context '#create_table' do
    let(:database) { Quarantine::Databases::DynamoDB.new(region: 'us-west-1') }

    it 'has arguments mapped and splatterd correctly' do
      attributes = [
        { attribute_name: 'a1', attribute_type: 'S', key_type: 'HASH' },
        { attribute_name: 'a2', attribute_type: 'S', key_type: 'RANGE' }
      ]

      additional_arguments = {
        a3: { a4: 'a4', a5: 'a5' },
        a6: 'a6'
      }

      expect(database.dynamodb).to receive(:create_table).with(
        table_name: 'foo',
        attribute_definitions: [
          { attribute_name: 'a1', attribute_type: 'S' },
          { attribute_name: 'a2', attribute_type: 'S' }
        ],
        key_schema: [
          { attribute_name: 'a1', key_type: 'HASH' },
          { attribute_name: 'a2', key_type: 'RANGE' }
        ],
        a3: { a4: 'a4', a5: 'a5' },
        a6: 'a6'
      )

      database.create_table('foo', attributes, additional_arguments)
    end

    it 'throws exception Quarantine::DatabaseError on AWS error' do
      error = Aws::DynamoDB::Errors::IndexNotFoundException.new(Quarantine, 'index not found')
      expect(database.dynamodb).to receive(:create_table).and_raise(error)
      expect { database.create_table('foo', [], {}) }.to raise_error(Quarantine::DatabaseError)
    end
  end
end
