require 'aws-sdk-dynamodb'
require 'quarantine/databases/base'
require 'quarantine/error'

class Quarantine
  module Databases
    class DynamoDB < Base
      attr_accessor :dynamodb

      def initialize(aws_region: 'us-west-1', aws_credentials: nil, **_additional_arguments)
        super()

        options = { region: aws_region }
        options[:credentials] = aws_credentials if aws_credentials

        @dynamodb = Aws::DynamoDB::Client.new(options)
      end

      def scan(table_name)
        begin
          result = dynamodb.scan(table_name: table_name)
        rescue Aws::DynamoDB::Errors::ServiceError
          raise Quarantine::DatabaseError
        end

        result&.items
      end

      def batch_write_item(table_name, items, additional_attributes = {}, dedup_keys = %w[id full_description])
        return if items.empty?

        # item_a is a duplicate of item_b if all values for each dedup_key in both item_a and item_b match
        is_a_duplicate = ->(item_a, item_b) { dedup_keys.all? { |key| item_a[key] == item_b[key] } }

        scanned_items = scan(table_name)

        deduped_items = items.reject do |item|
          scanned_items.any? do |scanned_item|
            is_a_duplicate.call(item.to_string_hash, scanned_item)
          end
        end

        return if deduped_items.empty?

        dynamodb.batch_write_item(
          request_items: {
            table_name => deduped_items.map do |item|
              {
                put_request: {
                  item: { **item.to_hash, **additional_attributes }
                }
              }
            end
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      def delete_item(table_name, keys)
        dynamodb.delete_item(
          table_name: table_name,
          key: {
            **keys
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      def create_table(table_name, attributes, additional_arguments = {})
        dynamodb.create_table(
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
