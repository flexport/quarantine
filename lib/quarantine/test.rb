class Quarantine
  class Test
    attr_accessor :id, :full_description, :location, :extra_attributes

    def initialize(id, full_description, location, extra_attributes)
      @id = id
      @full_description = full_description
      @location = location
      @extra_attributes = extra_attributes
    end

    def to_hash
      {
        id: id,
        full_description: full_description,
        location: location,
        extra_attributes: extra_attributes
      }
    end
  end
end
