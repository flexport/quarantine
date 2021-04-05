# typed: strict

class Quarantine
  module Databases
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      Item = T.type_alias do
        {
          'id' => String,
          'last_status' => String,
          'consecutive_passes' => Integer,
          'full_description' => String,
          'location' => String,
          'extra_attributes' => T.untyped
        }
      end

      sig { abstract.params(table_name: String).returns(T::Enumerable[Item]) }
      def fetch_items(table_name); end

      sig do
        abstract.params(
          table_name: String,
          items: T::Array[Item],
        ).void
      end
      def write_items(table_name, items); end
    end
  end
end
