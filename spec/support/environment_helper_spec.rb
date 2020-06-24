require 'spec_helper'

describe EnvironmentHelper do
  let(:test_example_value) { 'xyz' }

  around(:each) do |example|
    ENV['test_example'] = test_example_value
    example.run
    ENV.delete('test_example')
  end

  it 'modifies the environment in isolation' do
    with_environment(test_example: 'abc') do
      expect(ENV['test_example']).to eql 'abc'
    end
  end

  it 'restores the previous environment' do
    with_environment(test_example: 'abc') {}
    expect(ENV['test_example']).to eql test_example_value
  end
end
