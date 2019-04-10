# Quarantine
The purpose of `quarantine` is to provide a run-time solution to disabling flaky tests.

## General Workflow
1. quarantine identifies a test is flaky and decides it should be added to the list of quarantined tests
   &downarrow;
2. A Jira ticket is automatically created to fix the flaky test
   &downarrow;
3. All subsequent builds will pass the quarantined flaky test, regardless if it actually passes or fails
   &downarrow;
4. The flaky test has been fixed and the Jira ticket is closed resulting in the test automatically being removed from the list of quarantined tests

## Setup Quarantine Gem

1. Create tables in your database required for the gem the upload and pull quarantined test info
```
bundle exec quarantine_dynamodb -h            # see all options

bundle exec quarantine_dynamodb -r us-west-1  # create the tables in us-west-1 in aws dynamodb
                                              # with default table names "quarantine_list" and
                                              # and "master_failed_tests"
```

2. In your `spec_helper.rb` include the quarantine and rspec-retry gem
```
require "quarantine"
require "rspec-retry"
```
3. Configure rspec-retry to retry failed tests
```
config.around(:each) do |example|
  example.run_with_retry(retry: 2)
end
```
4. Bind quarantine to RSpec in a CI environment
```
if ENV[CI] && ENV[branch] == "master"
  Quarantine.bind
end
```
5. Setup two tables in dynamodb in the correct region with the correct fields
```
@TODO: script to create tables in region
```


## How to Set-up Development Locally

1. Setup dynamodb table names in AWS and add configurations
```
RSpec.configuration.quarantine_list_table = "table name"
RSpec.configuration.quarantine_failed_tests_table = "table name"
```

2. Add some non-deterministic tests
```
it "flaky test" do
  expect(1).to eq(Random.rand(2))
end
```

3. Run rspec a couple time until there is the case where the test fails on the first try but passes on the second try.
```rspec some_file_with_flaky_test_spec.rb```

4. Check dynamodb table `RSpec.configuration.quarantine_list_table` and confirm that the test was uploaded.
 
## Configuration Variables

Go to `spec/spec_helper.rb` and set configuration variables through:
```
RSpec.configure do |config|
    RSpec.configuration.VAR_NAME = VALUE
end
```

`quarantine_list_table, default: "quarantine_list"`

DynamoDB table where flaky tests are uploaded and quarantined tests are downloaded

`quarantine_failed_tests_table, default: "master_failed_tests"`

DynamoDB table where failed test are uploaded

`skip_quarantined_tests, default: true`

Flag to determine if quarantined tests should be skipped and passed automatically

`quarantine_record_failed_tests, default: true`

Flag to determine if failed tests should be recorded

`quarantine_record_flaky_tests, default: true`

Flag to determine if flaky tests should be recorded

`remove_duplicate_tests, default: true`

Flag to determine if duplicate test id's in the `quarantine_list_table` should have the oldest test id deleted (determined by build number)

`quarantine_logging, default: true`

Flag to determine if logs should be sent to the `rspec` formatters.
Logs include:
- tests that were successfully quarantined
- tests that were identified as flaky
- non-critical dynamodb failures


## FAQs

#### Why are quarantined tests not being skipped locally?

The `quarantine` gem is configured to run in specific `CI` environments. Therefore when testing locally, you need to pass in these `ENV` variables to get knapsack to run.

```
BUILDKITE_BRANCH="master" BUILDKITE_TRIGGERED_FROM_BUILD_PIPELINE_SLUG="master-tests" rspec
```

#### Why is dynamodb failing locally?

The AWS client loads credentials from the following locations:
- `ENV['AWS_ACCESS_KEY_ID']` and `ENV['AWS_SECRET_ACCESS_KEY']`
- `Aws.config[:credentials]`
- The shared credentials ini file at `~/.aws/credentials`

To get AWS credentials, please contact your AWS administrator to get access to dynamodb and create your credentials through IAM.

More detailed information can be found: [AWS documentation](https://docs.aws.amazon.com/sdkforruby/api/Aws/S3/Client.html)

#### Why is example.clear_exception failing locally?
