# typed: strict

require 'aws-sdk-dynamodb'
require 'quarantine/databases/base'
require 'quarantine/error'

class Quarantine
  module Databases
    class DynamoDB < Base
      extend T::Sig

      Attribute = T.type_alias { { attribute_name: String, attribute_type: String, key_type: String } }

      sig { returns(Aws::DynamoDB::Client) }
      attr_accessor :dynamodb

      sig { params(options: T::Hash[T.untyped, T.untyped]).void }
      def initialize(options)
        super()

        @dynamodb = T.let(Aws::DynamoDB::Client.new(options), Aws::DynamoDB::Client)
      end

      sig { override.params(table_name: String).returns(T::Enumerable[Item]) }
      def scan(table_name)
        begin
          result = @dynamodb.scan(table_name: table_name)
        rescue Aws::DynamoDB::Errors::ServiceError
          raise Quarantine::DatabaseError
        end

        result.items
      end

      sig do
        override.params(
          table_name: String,
          items: T::Array[Item],
          additional_attributes: T::Hash[T.untyped, T.untyped]
        ).void
      end
      def batch_write_item(table_name, items, additional_attributes = {})
        @dynamodb.batch_write_item(
          request_items: {
            table_name => items.map do |item|
              {
                put_request: {
                  item: item.to_hash.merge(additional_attributes)
                }
              }
            end
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      sig { params(table_name: String, keys: T::Hash[T.untyped, T.untyped]).void }
      def delete_item(table_name, keys)
        @dynamodb.delete_item(
          table_name: table_name,
          key: {
            **keys
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      sig do
        params(
          table_name: String,
          attributes: T::Array[Attribute],
          additional_arguments: T::Hash[T.untyped, T.untyped]
        ).void
      end
      def create_table(table_name, attributes, additional_arguments = {})
        @dynamodb.create_table(
          {
            table_name: table_name,
            attribute_definitions: attributes.map do |attribute|
              {
                attribute_name: attribute[:attribute_name],
                attribute_type: attribute[:attribute_type]
              }
            end,
            key_schema: attributes.map do |attribute|
              {
                attribute_name: attribute[:attribute_name],
                key_type: attribute[:key_type]
              }
            end,
            **additional_arguments
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end
    end
  end
end
