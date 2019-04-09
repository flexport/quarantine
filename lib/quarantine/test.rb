# TEAM: backend_infra

class Quarantine
  class Test
    attr_accessor :id
    attr_accessor :full_description
    attr_accessor :location
    attr_accessor :build_number

    def initialize(id, full_description, location, build_number)
      @id = id
      @full_description = full_description
      @location = location
      @build_number = build_number
    end

    def to_hash
      {
        id: id,
        full_description: full_description,
        location: location,
        build_number: build_number,
      }
    end
  end
end
