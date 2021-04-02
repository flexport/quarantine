# typed: strict

class Quarantine
  class Test < T::Struct
    extend T::Sig

    const :id, String
    const :status, Symbol
    const :consecutive_passes, Integer
    const :full_description, String
    const :location, String
    const :extra_attributes, T::Hash[T.untyped, T.untyped]

    sig { returns(Quarantine::Databases::Base::Item) }
    def to_hash
      {
        'id' => id,
        'last_status' => status.to_s,
        'consecutive_passes' => consecutive_passes,
        'full_description' => full_description,
        'location' => location,
        'extra_attributes' => extra_attributes
      }
    end
  end
end
