# typed: false
require 'spec_helper'

describe Quarantine::Test do
  context '#initialize' do
    it 'all instance variables to argument values' do
      test = Quarantine::Test.new(
        id: 'id',
        status: :quarantined,
        consecutive_passes: 1,
        full_description: 'full_description',
        location: 'location',
        extra_attributes: { attr: 'value' }
      )
      expect(test.id).to eq('id')
      expect(test.status).to eq(:quarantined)
      expect(test.full_description).to eq('full_description')
      expect(test.location).to eq('location')
      expect(test.extra_attributes).to eq(attr: 'value')
    end
  end

  context '#to_hash' do
    it 'returns a hash of the Quarantine::Test object' do
      test = Quarantine::Test.new(
        id: 'id',
        status: :quarantined,
        consecutive_passes: 1,
        full_description: 'full_description',
        location: 'location',
        extra_attributes: { attr: 'value' }
      )
      result = {
        'id' => 'id',
        'last_status' => 'quarantined',
        'consecutive_passes' => 1,
        'full_description' => 'full_description',
        'location' => 'location',
        'extra_attributes' => { attr: 'value' }
      }
      expect(test.to_hash).to eq(result)
    end
  end
end
