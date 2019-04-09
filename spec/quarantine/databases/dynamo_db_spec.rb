# TEAM: backend_infra

require "spec_helper"

describe Quarantine::Databases::DynamoDB do
  context " #initialize" do
    it " all instance variables to the default value" do
      database = Quarantine::Databases::DynamoDB.new({additional_arg: "foo"})

      expect(database.dynamodb).to be_a(Aws::DynamoDB::Client)
      expect(database.dynamodb.config.region).to eq("us-west-1")
    end

    it " aws region to us-east-2" do
      database = Quarantine::Databases::DynamoDB.new({aws_region: "us-east-2"})

      expect(database.dynamodb).to be_a(Aws::DynamoDB::Client)
      expect(database.dynamodb.config.region).to eq("us-east-2")
    end
  end

  context " #scan" do
    test1 = {
      "full_description" => "quarantined_test_1",
      "id" => "1",
      "location" => "line 1",
      "build_number" => "123",
    }

    test2 = {
      "full_description" => "quarantined_test_2",
      "id" => "2",
      "location" => "line 2",
      "build_number" => "-1",
    }

    let(:dynamodb) { Aws::DynamoDB::Client.new(stub_responses: true) }
    let(:stub_multiple_tests) { dynamodb.stub_data(:scan, {items: [test1, test2]}) }
    let(:database) { Quarantine::Databases::DynamoDB.new }

    before(:each) do
      database.dynamodb = dynamodb
    end

    it " is called with the correct table name" do
      expect(database.dynamodb).to receive(:scan).with({table_name: "foo"}).once
      database.scan("foo")
    end

    it " returns all items queried in the scan" do
      database.dynamodb.stub_responses(:scan, stub_multiple_tests)
      items = database.scan("foo")

      expect(items.length).to eq(2)
      expect(items[0]["id"]).to eq("1")
      expect(items[0]["full_description"]).to eq("quarantined_test_1")
      expect(items[0]["location"]).to eq("line 1")
      expect(items[0]["build_number"]).to eq("123")

      expect(items[1]["id"]).to eq("2")
      expect(items[1]["full_description"]).to eq("quarantined_test_2")
      expect(items[1]["location"]).to eq("line 2")
      expect(items[1]["build_number"]).to eq("-1")
    end

    it " throws exception Quarantine::DatabaseError on AWS errors" do
      allow(database.dynamodb).to receive(:scan).and_raise(Aws::DynamoDB::Errors::TableNotFoundException.new(
                                                             Quarantine,
                                                             "table not found",
      ))
      expect { database.scan("foo") }.to raise_error(Quarantine::DatabaseError)
    end
  end

  context " #batch_write_item" do
    item1 = {x: "foo", y: "bar"}

    item2 = {x: "foo2", y: "bar2"}

    let(:database) { Quarantine::Databases::DynamoDB.new }
    let(:items) { [item1, item2] }
    let(:additional_attributes) { {a: "a", b: "b"} }

    it " has arguments splatted correctly" do
      expect(database.dynamodb).to receive(:batch_write_item).with({
        request_items: {
          "foo" => [
            {
              put_request: {
                item: {
                  x: "foo",
                  y: "bar",
                  a: "a",
                  b: "b",
                },
              },
            },
            {
              put_request: {
                item: {
                  x: "foo2",
                  y: "bar2",
                  a: "a",
                  b: "b",
                },
              },
            },
          ],
        },
      }).once

      database.batch_write_item("foo", items, additional_attributes)
    end

    it " throws exception Quarantine::DatabaseError on AWS errors" do
      allow(database.dynamodb).to receive(:batch_write_item).and_raise(Aws::DynamoDB::Errors::LimitExceededException.new(
                                                                         Quarantine,
                                                                         "limit exceeded",
      ))
      expect { database.batch_write_item("foo", []) }.to raise_error(Quarantine::DatabaseError)
    end
  end

  context " #delete_item" do
    let(:database) { Quarantine::Databases::DynamoDB.new }

    it " has arguments splatted correctly" do
      expect(database.dynamodb).to receive(:delete_item).with({
        table_name: "foo",
        key: {id: "1", build_number: "123"},
      })

      database.delete_item("foo", {id: "1", build_number: "123"})
    end

    it " throws exception Quarantine::DatabaseError on AWS errors" do
      allow(database.dynamodb).to receive(:delete_item).and_raise(Aws::DynamoDB::Errors::IndexNotFoundException.new(
                                                                    Quarantine,
                                                                    "index not found",
      ))
      expect { database.delete_item("foo", {id: "1"}) }.to raise_error(Quarantine::DatabaseError)
    end
  end
end
