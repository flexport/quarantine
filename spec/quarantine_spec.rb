# typed: false
require 'spec_helper'

describe Quarantine do
  let(:database_options) do
    {
      type: :dynamodb,
      region: 'us-west-1'
    }
  end

  let(:options) do
    {
      database: database_options,
      test_statuses_table_name: 'foo',
      logging: true,
      log: ->(message) { puts message }
    }
  end

  context '#on_start' do
    test1 = {
      'full_description' => 'quarantined_test_1',
      'id' => '1',
      'location' => 'line 1',
      'last_status' => 'quarantined',
      'consecutive_passes' => 1,
      'extra_attributes' => {}
    }

    test2 = {
      'full_description' => 'quarantined_test_2',
      'id' => '2',
      'location' => 'line 2',
      'last_status' => 'quarantined',
      'consecutive_passes' => 1,
      'extra_attributes' => {}
    }

    let(:quarantine) { Quarantine.new(options) }
    let(:dynamodb) { Aws::DynamoDB::Client.new({ stub_responses: true }) }
    let(:stub_multiple_tests) { dynamodb.stub_data(:scan, { items: [test1, test2] }) }

    it 'correctly stores quarantined tests pulled from DynamoDB' do
      expect(quarantine.database).to receive(:fetch_items).and_return([test1, test2])

      quarantine.on_start

      expect(quarantine.old_tests.size).to eq(2)
      expect(quarantine.old_tests.key?('1')).to eq(true)
      expect(quarantine.old_tests.key?('2')).to eq(true)
    end

    it 'if dynamodb.scan fails, make sure an exception is throw' do
      error = Aws::DynamoDB::Errors::LimitExceededException.new(Quarantine, 'limit exceeded')
      expect(quarantine.database.dynamodb).to receive(:scan).and_raise(error)

      expect { quarantine.on_start }.to raise_error(Quarantine::DatabaseError)

      expect(options[:log]).to receive(:call)
      expect(options[:log]).to receive(:call).with(
        include('Aws::DynamoDB::Errors::LimitExceededException: limit exceeded')
      )

      quarantine.on_complete
    end
  end

  def set_up_test_statuses(quarantine, tests)
    expect(quarantine.database).to receive(:fetch_items).and_return(tests)

    quarantine.on_start
  end

  context '#on_test' do
    let(:quarantine) { Quarantine.new(options) }

    it 'adds a new flaky test to @tests' do |example|
      quarantine.on_test(example, :quarantined, passed: true)

      expect(quarantine.tests.length).to eq(1)
      expect(quarantine.tests[example.id].id).to eq(example.id)
      expect(quarantine.tests[example.id].status).to eq(:quarantined)
      expect(quarantine.tests[example.id].consecutive_passes).to eq(1)
      expect(quarantine.tests[example.id].full_description).to eq(example.full_description)
      expect(quarantine.tests[example.id].location).to eq(example.location)
      expect(quarantine.tests[example.id].extra_attributes).to eq({})
    end

    it 'adds a new failed test to @tests' do |example|
      quarantine.on_test(example, :quarantined, passed: false)

      expect(quarantine.tests.length).to eq(1)
      expect(quarantine.tests[example.id].id).to eq(example.id)
      expect(quarantine.tests[example.id].status).to eq(:quarantined)
      expect(quarantine.tests[example.id].consecutive_passes).to eq(0)
      expect(quarantine.tests[example.id].full_description).to eq(example.full_description)
      expect(quarantine.tests[example.id].location).to eq(example.location)
      expect(quarantine.tests[example.id].extra_attributes).to eq({})
    end

    context 'with old test' do
      it 'adds a flaky test to @tests' do |example|
        set_up_test_statuses(
          quarantine,
          [{
            'id' => example.id,
            'last_status' => 'quarantined',
            'consecutive_passes' => 5,
            'full_description' => 'quarantined_test',
            'location' => 'line 1',
            'extra_attributes' => {}
          }]
        )

        quarantine.on_test(example, :quarantined, passed: true)

        expect(quarantine.tests.length).to eq(1)
        expect(quarantine.tests[example.id].id).to eq(example.id)
        expect(quarantine.tests[example.id].status).to eq(:quarantined)
        expect(quarantine.tests[example.id].consecutive_passes).to eq(6)
      end

      context 'with release_at_consecutive_passes' do
        let(:options) { { database: database_options, release_at_consecutive_passes: 6 } }

        it 'releases the test' do |example|
          set_up_test_statuses(
            quarantine,
            [{
              'id' => example.id,
              'last_status' => 'quarantined',
              'consecutive_passes' => 5,
              'full_description' => 'quarantined_test',
              'location' => 'line 1',
              'extra_attributes' => {}
            }]
          )

          quarantine.on_test(example, :quarantined, passed: true)

          expect(quarantine.tests.length).to eq(1)
          expect(quarantine.tests[example.id].id).to eq(example.id)
          expect(quarantine.tests[example.id].status).to eq(:passing)
          expect(quarantine.tests[example.id].consecutive_passes).to eq(6)
        end
      end
    end

    context 'with extra attributes' do
      let(:options) { { database: database_options, extra_attributes: proc { { build_number: 5 } } } }

      it 'adds a new flaky test to @tests' do |example|
        quarantine.on_test(example, :quarantined, passed: true)

        expect(quarantine.tests.length).to eq(1)
        expect(quarantine.tests[example.id].id).to eq(example.id)
        expect(quarantine.tests[example.id].status).to eq(:quarantined)
        expect(quarantine.tests[example.id].full_description).to eq(example.full_description)
        expect(quarantine.tests[example.id].location).to eq(example.location)
        expect(quarantine.tests[example.id].extra_attributes).to eq(build_number: 5)
      end
    end
  end

  context '#on_complete' do
    let(:quarantine) do
      new_options = options.merge(
        test_statuses_table_name: 'test_statuses',
        failsafe_limit: failsafe_limit,
        record_tests: true
      )
      Quarantine.new(new_options)
    end
    let(:failsafe_limit) { 10 }

    it 'uploads with a test' do |example|
      quarantine.on_test(example, :quarantined, passed: true)
      expect(quarantine.database).to receive(:write_items)
      quarantine.on_complete
    end

    it "doesn't upload with no tests" do |_example|
      expect(quarantine.database).to_not receive(:write_items)
      quarantine.on_complete
    end

    context 'with low failsafe limit' do
      let(:failsafe_limit) { 1 }

      it "doesn't upload" do |example|
        quarantine.on_test(example, :quarantined, passed: true)
        expect(quarantine.database).to_not receive(:write_items)
        quarantine.on_complete
      end
    end
  end

  context '#test_quarantined?' do
    let(:quarantine) { Quarantine.new(options) }

    it 'returns true on quarantined test' do |example|
      set_up_test_statuses(
        quarantine,
        [{
          'id' => example.id,
          'last_status' => 'quarantined',
          'consecutive_passes' => 1,
          'full_description' => 'quarantined_test',
          'location' => 'line 1',
          'extra_attributes' => {}
        }]
      )

      expect(quarantine.test_quarantined?(example)).to eq(true)
    end

    it 'returns false on a non-quarantined test' do |example|
      expect(quarantine.test_quarantined?(example)).to eq(false)
    end
  end
end
