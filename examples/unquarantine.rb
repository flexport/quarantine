#
# This is an very basic example of a webhook that will unquarantine tests automatically
#
# Add this webhook into Jira which should be called everytime
# a quarantined test ticket is (closed|duplicate|done|cancelled)
#

class Webhooks::JiraController < ApplicationController

  # POST request
  def quarantine

    # When jira calls this webhook, in the body, it should provide
    # the key to the Jira ticket which should have previously been
    # saved in examples/create_tickets.rb
    jira_key = params["jira"]["key"]
    dynamodb = Aws::DynamoDB::Client.new(region: "us-west-1")

    begin
      # In dynamodb, add a global secondary index on the jira_key attribute
      result = dynamodb.query({
        index_name: "jira_key",
        table_name: "quarantine_list",
        key_condition_expression: "jira_key=:jira_key",
        expression_attribute_values: {":jira_key": jira_key},
      })

      if result.count == 0
        # send alert that quarantined test was unable to be removed
      elsif result.count == 1
        quarantined_test = result.items[0]

        # unquarantined the test related to the ticket
        dynamodb.delete_item(
          table_name: "quarantine_list",
          key: {
            id: quarantined_test["id"],
            build_number: quarantined_test["build_number"],
          },
        )
      else
        # send alert that multiple quarantined tests are related to the same ticket
      end
    rescue Aws::DynamoDB::Errors::ServiceError
      # send alert that quarantined test was unabled to be removed
    end
  end
end