class Quarantine
  module Databases
    class Base
      def scan
        raise NotImplementedError
      end

      def batch_write_item
        raise NotImplementedError
      end
    end
  end
end
