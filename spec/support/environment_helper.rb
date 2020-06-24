require 'climate_control'

module EnvironmentHelper
  # https://github.com/thoughtbot/climate_control#usage
  def with_environment(keys, &block)
    ClimateControl.modify(keys, &block)
  end
end
