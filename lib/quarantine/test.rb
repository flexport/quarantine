class Quarantine
  class Test
    attr_accessor :id, :status, :full_description, :location, :extra_attributes

    def initialize(id, status, full_description, location, extra_attributes)
      @id = id
      @status = status
      @full_description = full_description
      @location = location
      @extra_attributes = extra_attributes
    end

    def to_hash
      {
        id: id,
        last_status: status,
        full_description: full_description,
        location: location,
        extra_attributes: extra_attributes
      }
    end
  end
end
