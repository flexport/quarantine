# typed: strict

class Quarantine
  class Error < StandardError; end

  # Raised when a database error has occurred
  # TODO(ezhu): expand error messages to cover more specific error messages
  class DatabaseError < Error; end

  # Raised when quarantine does not know how to upload a specific test
  class UnknownUploadError < Error; end

  # Quarantine does not work with the specified database
  class UnsupportedDatabaseError < Error; end
end
