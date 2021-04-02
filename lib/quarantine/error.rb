# typed: strict

class Quarantine
  class Error < StandardError; end

  # Raised when a database error has occured
  # TODO(ezhu): expand error messages to cover more specific error messages
  class DatabaseError < Error; end

  # Raised when quarantine does not know how to upload a specific test
  class UnknownUploadError < Error; end

  # Quarantine does not work with the specificed database
  class UnsupportedDatabaseError < Error; end
end
