require 'spec_helper'

describe Quarantine do
  context '#initialize' do
    it 'all instance variables to the default value' do
      quarantine = Quarantine.new

      expect(quarantine.database).to be_a(Quarantine::Databases::DynamoDB)
      expect(quarantine.quarantine_map).to eq({})
      expect(quarantine.failed_tests).to eq([])
      expect(quarantine.flaky_tests).to eq([])
    end
  end

  context '#fetch_quarantine_list' do
    test1 = {
      'full_description' => 'quarantined_test_1',
      'id' => '1',
      'location' => 'line 1',
      'build_number' => '123'
    }

    test2 = {
      'full_description' => 'quarantined_test_2',
      'id' => '2',
      'location' => 'line 2',
      'build_number' => '-1'
    }

    test1_duplicate = {
      'full_description' => 'quarantined_test_1',
      'id' => '1',
      'location' => 'line 3',
      'build_number' => '124'
    }

    let(:quarantine) { Quarantine.new }
    let(:dynamodb) { Aws::DynamoDB::Client.new({ stub_responses: true }) }
    let(:stub_multiple_tests) { dynamodb.stub_data(:scan, { items: [test1, test2] }) }
    let(:stub_duplicate_tests_replace) do
      dynamodb.stub_data(
        :scan,
        { items: [
          test1,
          test1_duplicate
        ] }
      )
    end
    let(:stub_duplicate_tests_add) do
      dynamodb.stub_data(
        :scan,
        { items: [
          test1_duplicate,
          test1
        ] }
      )
    end

    it 'correctly stores quarantined tests pulled from DynamoDB' do
      allow(quarantine.database).to receive(:scan).and_return(stub_multiple_tests.items)

      quarantine.fetch_quarantine_list

      expect(quarantine.quarantine_map.size).to eq(2)
      expect(quarantine.quarantine_map.key?('1')).to eq(true)
      expect(quarantine.quarantine_map.key?('2')).to eq(true)
    end

    it 'if duplicate test ids and the quarantine_map test is older, replace it with the newer test' do
      allow(quarantine.database).to receive(:scan).and_return(stub_duplicate_tests_replace.items)
      quarantine.fetch_quarantine_list

      expect(quarantine.quarantine_map.size).to eq(1)
      expect(quarantine.quarantine_map.key?('1')).to eq(true)
      expect(quarantine.quarantine_map['1'].build_number).to eq('124')
    end

    it 'if duplicate test ids and the quarantine_map test is newer, add the older test to duplicate_tests' do
      allow(quarantine.database).to receive(:scan).and_return(stub_duplicate_tests_add.items)
      quarantine.fetch_quarantine_list

      expect(quarantine.quarantine_map.size).to eq(1)
      expect(quarantine.quarantine_map.key?('1')).to eq(true)
      expect(quarantine.quarantine_map['1'].build_number).to eq('124')
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
    let(:quarantine) { Quarantine.new }

    it 'adds the failed test to the @failed_test array' do |example|
      quarantine.record_failed_test(example)

      expect(quarantine.failed_tests.length).to eq(1)
      expect(quarantine.failed_tests[0].id).to eq(example.id)
      expect(quarantine.failed_tests[0].full_description).to eq(example.full_description)
      expect(quarantine.failed_tests[0].location).to eq(example.location)
      expect(quarantine.failed_tests[0].build_number).to eq(quarantine.ci_build_number)
    end

    context 'when BUILDKITE_BUILD_NUMBER is defined' do
      it 'assigns its value to build_number' do |example|
        with_environment(BUILDKITE_BUILD_NUMBER: '1234') do
          quarantine.record_failed_test(example)

          expect(quarantine.failed_tests[0].build_number).to eq('1234')
        end
      end
    end

    context 'when BUILD_NUMBER is defined' do
      it 'assigns its value to build_number' do |example|
        with_environment(BUILD_NUMBER: '9876') do
          quarantine.record_failed_test(example)

          expect(quarantine.failed_tests[0].build_number).to eq('9876')
        end
      end
    end

    context 'when neither BUILDKITE_JOB_ID nor BUILD_NUMBER are defined' do
      it 'assigns -1 to build_number' do |example|
        quarantine.record_failed_test(example)

        expect(quarantine.failed_tests[0].build_number).to eq('-1')
      end
    end
  end

  context '#record_flaky_test' do
    let(:quarantine) { Quarantine.new }

    it 'adds the flaky test to the @flaky_test array' do |example|
      quarantine.record_flaky_test(example)

      expect(quarantine.flaky_tests.length).to eq(1)
      expect(quarantine.flaky_tests[0].id).to eq(example.id)
      expect(quarantine.flaky_tests[0].full_description).to eq(example.full_description)
      expect(quarantine.flaky_tests[0].location).to eq(example.location)
      expect(quarantine.flaky_tests[0].build_number).to eq(quarantine.ci_build_number)
    end

    context 'when BUILDKITE_BUILD_NUMBER is defined' do
      it 'assigns its value to build_number' do |example|
        with_environment(BUILDKITE_BUILD_NUMBER: '1234') do
          quarantine.record_flaky_test(example)

          expect(quarantine.flaky_tests[0].build_number).to eq('1234')
        end
      end
    end

    context 'when BUILD_NUMBER is defined' do
      it 'assigns its value to build_number' do |example|
        with_environment(BUILD_NUMBER: '9876') do
          quarantine.record_flaky_test(example)

          expect(quarantine.flaky_tests[0].build_number).to eq('9876')
        end
      end
    end

    context 'when neither BUILDKITE_JOB_ID nor BUILD_NUMBER are defined' do
      it 'assigns -1 to build_number' do |example|
        quarantine.record_flaky_test(example)

        expect(quarantine.flaky_tests[0].build_number).to eq('-1')
      end
    end
  end

  context '#test_quarantined?' do
    let(:quarantine) { Quarantine.new }

    it 'returns true on quarantined test' do |example|
      quarantine.quarantine_map.store(
        example.id,
        Quarantine::Test.new(
          example.id,
          example.full_description,
          example.location,
          '123'
        )
      )
      expect(quarantine.test_quarantined?(example)).to eq(true)
    end

    it 'returns false on a non-quarantined test' do |example|
      expect(quarantine.test_quarantined?(example)).to eq(false)
    end
  end

  context '#pass_flaky_test' do
    let(:quarantine) { Quarantine.new }

    it 'passes a failing test' do |example|
      example.set_exception(StandardError.new)
      quarantine.pass_flaky_test(example)
    end
  end
end
