require 'spec_helper'

describe Quarantine::Test do
  context '#initialize' do
    it 'all instance variables to argument values' do
      test = Quarantine::Test.new('id', 'full_description', 'location', 'build_number')
      expect(test.id).to eq('id')
      expect(test.full_description).to eq('full_description')
      expect(test.location).to eq('location')
      expect(test.build_number).to eq('build_number')
    end
  end

  context '#to_hash' do
    it 'returns a hash of the Quarantine::Test object' do
      test = Quarantine::Test.new('id', 'full_description', 'location', 'build_number')
      result = {
        id: 'id',
        full_description: 'full_description',
        location: 'location',
        build_number: 'build_number'
      }
      expect(test.to_hash).to eq(result)
    end
  end
end
