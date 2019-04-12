#
# This is an very basic example of a script that will create tickets for flaky tests
#
# A lot more can be added to enrich ticket creation such as:
#   - labels for tickets
#   - assigning tickets to teams
#   - better error checking
#   - adding most attributes to quarantined tests
#       - build links
#       - created at/updated_at status

# Jira client to create ticket
require 'jira-ruby'

# AWS client to access quarantine list
require 'aws-sdk'

dynamodb = Aws::DynamoDB::Client.new({ region: 'us-west-1' })
jira_client = JIRA::Client.new(JIRA_OPTIONS)

# Get all quarantined tests that do not have a jira ticket created yet
tests = dynamodb.scan({
                        table_name: 'quarantine_list',
                        filter_expression: 'attribute_not_exists(jira_key)'
                      })

# iterate through all tests that do not have jira tickets
tests.each do |test|
  # Create the jira ticket for the particular test
  #
  # A lot more information can be added to your implementation, this
  # should just give a rough idea on some basic fields for the Jira ticket
  issue = jira_client.Issue.build
  issue.save({ 'fields' => {
               'summary' => 'TITLE',
               'project' => { 'key' => PROJECT_KEY },
               'description' => DESCRIPTION
             } })

  # Update the quarantined tests so only 1 jira ticket is created
  dynamodb.update_item({
                         table_name: 'quarantine_list',
                         key: {
                           id: test['id'],
                           build_number: test['build_number']
                         },
                         update_expression: 'jira_key = :jira_key',
                         expression_attribute_values: {
                           ':jira_key' => jira_key
                         }
                       })
end
