require 'aws-sdk'
require 'quarantine/databases/base'
require 'quarantine/error'

class Quarantine
  module Databases  
    class DynamoDB < Base
      attr_accessor :dynamodb

      def initialize(aws_region: 'us-west-1', **_additional_arguments)
        @dynamodb = Aws::DynamoDB::Client.new({ region: aws_region })
      end

      def scan(table_name)
        begin
          result = dynamodb.scan({ table_name: table_name })
        rescue Aws::DynamoDB::Errors::ServiceError
          raise Quarantine::DatabaseError
        end

        result&.items
      end

      def batch_write_item(table_name, items, additional_attributes = {})
        dynamodb.batch_write_item(
          { request_items: {
            table_name => items.map do |item|
              {
                put_request: {
                  item: { **item.to_hash, **additional_attributes }
                }
              }
            end
          } }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      def delete_item(table_name, keys)
        dynamodb.delete_item(
          {
            table_name: table_name,
            key: {
              **keys
            }
          }
        )
      rescue Aws::DynamoDB::Errors::ServiceError
        raise Quarantine::DatabaseError
      end

      def create_table(table_name, attributes, additional_arguments = {})
        dynamodb.create_table(
          {
            table_name: table_name,
            :attribute_definitions => attributes.map do |attribute|
              {
                attribute_name: attribute[:attribute_name],
                attribute_type: attribute[:attribute_type]
              }
            end,
            :key_schema => attributes.map do |attribute|
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
