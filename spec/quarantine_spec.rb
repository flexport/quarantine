require 'spec_helper'

describe Quarantine do
  before(:all) do
    Quarantine.bind_rspec
  end

  let(:database_options) do
    {
      type: :dynamodb,
      region: 'us-west-1'
    }
  end

  let(:options) do
    {
      database: database_options
    }
  end

  context '#fetch_quarantine_list' do
    test1 = {
      'full_description' => 'quarantined_test_1',
      'id' => '1',
      'location' => 'line 1'
    }

    test2 = {
      'full_description' => 'quarantined_test_2',
      'id' => '2',
      'location' => 'line 2'
    }

    let(:quarantine) { Quarantine.new(options) }
    let(:dynamodb) { Aws::DynamoDB::Client.new({ stub_responses: true }) }
    let(:stub_multiple_tests) { dynamodb.stub_data(:scan, { items: [test1, test2] }) }

    it 'correctly stores quarantined tests pulled from DynamoDB' do
      allow(quarantine.database).to receive(:scan).and_return(stub_multiple_tests.items)

      quarantine.fetch_quarantine_list

      expect(quarantine.quarantined_ids.size).to eq(2)
      expect(quarantine.quarantined_ids.include?('1')).to eq(true)
      expect(quarantine.quarantined_ids.include?('2')).to eq(true)
    end

    it 'if dynamodb.scan fails, make sure an exception is throw' do
      error = Aws::DynamoDB::Errors::LimitExceededException.new(Quarantine, 'limit exceeded')
      allow(quarantine.database.dynamodb).to receive(:scan).and_raise(error)

      expect { quarantine.fetch_quarantine_list }.to raise_error(Quarantine::DatabaseError)

      expect(quarantine.summary[:database_failures].length).to eq(1)
      expect(quarantine.summary[:database_failures][0]).to eq(
        'Aws::DynamoDB::Errors::LimitExceededException: limit exceeded'
      )
    end
  end

  context '#record_failed_test' do
    let(:quarantine) { Quarantine.new(options) }

    it 'adds the failed test to the @failed_test array' do |example|
      quarantine.record_failed_test(example)

      expect(quarantine.failed_tests.length).to eq(1)
      expect(quarantine.failed_tests[0].id).to eq(example.id)
      expect(quarantine.failed_tests[0].full_description).to eq(example.full_description)
      expect(quarantine.failed_tests[0].location).to eq(example.location)
      expect(quarantine.failed_tests[0].extra_attributes).to eq({})
    end

    context 'with extra attributes' do
      let(:options) { { database: database_options, extra_attributes: proc { { build_number: 5 } } } }

      it 'adds the failed test to the @failed_test array' do |example|
        quarantine.record_failed_test(example)

        expect(quarantine.failed_tests.length).to eq(1)
        expect(quarantine.failed_tests[0].id).to eq(example.id)
        expect(quarantine.failed_tests[0].full_description).to eq(example.full_description)
        expect(quarantine.failed_tests[0].location).to eq(example.location)
        expect(quarantine.failed_tests[0].extra_attributes).to eq(build_number: 5)
      end
    end
  end

  context '#record_flaky_test' do
    let(:quarantine) { Quarantine.new(options) }

    it 'adds the flaky test to the @flaky_test array' do |example|
      quarantine.record_flaky_test(example)

      expect(quarantine.flaky_tests.length).to eq(1)
      expect(quarantine.flaky_tests[0].id).to eq(example.id)
      expect(quarantine.flaky_tests[0].full_description).to eq(example.full_description)
      expect(quarantine.flaky_tests[0].location).to eq(example.location)
      expect(quarantine.flaky_tests[0].extra_attributes).to eq({})
    end

    context 'with extra attributes' do
      let(:options) { { database: database_options, extra_attributes: proc { { build_number: 5 } } } }

      it 'adds the flaky test to the @flaky_test array' do |example|
        quarantine.record_flaky_test(example)

        expect(quarantine.flaky_tests.length).to eq(1)
        expect(quarantine.flaky_tests[0].id).to eq(example.id)
        expect(quarantine.flaky_tests[0].full_description).to eq(example.full_description)
        expect(quarantine.flaky_tests[0].location).to eq(example.location)
        expect(quarantine.flaky_tests[0].extra_attributes).to eq(build_number: 5)
      end
    end
  end

  context '#test_quarantined?' do
    let(:quarantine) { Quarantine.new(options) }

    it 'returns true on quarantined test' do |example|
      quarantine.quarantined_ids << example.id
      expect(quarantine.test_quarantined?(example)).to eq(true)
    end

    it 'returns false on a non-quarantined test' do |example|
      expect(quarantine.test_quarantined?(example)).to eq(false)
    end
  end

  context '#pass_flaky_test' do
    let(:quarantine) { Quarantine.new(options) }

    it 'passes a failing test' do |example|
      example.set_exception(StandardError.new)
      quarantine.pass_flaky_test(example)
    end
  end
end
