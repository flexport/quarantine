class Quarantine
  class Test
    attr_accessor :id, :status, :consecutive_passes, :full_description, :location, :extra_attributes

    def initialize(id, status, consecutive_passes, full_description, location, extra_attributes) # rubocop:disable Metrics/ParameterLists
      @id = id
      @status = status
      @consecutive_passes = consecutive_passes
      @full_description = full_description
      @location = location
      @extra_attributes = extra_attributes
    end

    def to_hash
      {
        id: id,
        last_status: status,
        consecutive_passes: consecutive_passes,
        full_description: full_description,
        location: location,
        extra_attributes: extra_attributes
      }
    end
  end
end
