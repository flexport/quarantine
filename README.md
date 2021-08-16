# Quarantine

[![Build Status](https://travis-ci.com/flexport/quarantine.svg?branch=master)](https://travis-ci.com/flexport/quarantine)

Quarantine automatically detects flaky tests (i.e. those which fail non-deterministically) and disables them until they're proven reliable.

Quarantine current supports the following testing frameworks. If you need an additional one, please file an issue or open a pull request.
- [RSpec](http://rspec.info/)

Quarantine should provide the necessary hooks for compatibility with any CI solution. If it's insufficient for yours, please file an issue or open a pull request.

## Getting started

Quarantine works in tandem with [RSpec::Retry](https://github.com/NoRedInk/rspec-retry). Add this to your `Gemfile` and run `bundle install`:

```rb
group :test do
  gem 'quarantine'
  gem 'rspec-retry'
end
```

In your `spec_helper.rb`, set up Quarantine and RSpec::Retry. See [RSpec::Retry](https://github.com/NoRedInk/rspec-retry)'s documentation for details of its configuration.

```rb
require 'quarantine'
require 'rspec/retry'

Quarantine::RSpecAdapter.bind

RSpec.configure do |config|
  # Also accepts `:credentials` to override the standard AWS credential chain
  config.quarantine_database = {type: :dynamodb, region: 'us-west-1'}
  # Prevent the list of flaky tests from being polluted by local development and PRs
  config.quarantine_record_tests = ENV["CI"] && ENV["BRANCH"] == "master"

  config.around(:each) do |example|
    example.run_with_retry(retry: 3)
  end
end
```

Quarantine comes with a CLI tool for setting up the necessary table in DynamoDB, if you use that database.

```sh
bundle exec quarantine_dynamodb -h    # See all options

bundle exec quarantine_dynamodb \     # Create the "test_statuses" table in us-west-1 in AWS DynamoDB
  --region us-west-1
```

## How It Works

A flaky test fails on the first run, but passes after being retried via RSpec::Retry.

```rb
require "spec_helper"

describe Quarantine do
  it "fails on the first run" do
    raise "error" if RSpec.current_example.attempts == 0
    # otherwise, pass
  end
end
```

```sh
$ CI=1 BRANCH=master bundle exec rspec <filename>
[quarantine] Quarantined tests:
  ./bar_spec.rb[1:1] Quarantine fails on the first run
```

When the build completes, all test statuses are written to the database. Flaky tests are marked `quarantined`, and will be executed in future builds, but any failures will be ignored.

A test can be removed from quarantine by updating the database manually (outside this gem), or by configuring `quarantine_release_at_consecutive_passes` to remove it after it passes on a certain number of builds in a row.

## Configuration

In `spec_helper.rb`, you can set configuration variables by doing:

```rb
RSpec.configure do |config|
  config.VAR_NAME = VALUE
end
```

- `quarantine_database`: Database configuration (see below), default: `{ type: :dynamodb, region: 'us-west-1' }`
- `test_statusus_table`: Table name for test statuses, default: `"test_statuses"`
- `skip_quarantined_tests`: Skipping quarantined tests during test runs default: `true`
- `quarantine_record_tests`: Recording test statuses, default: `true`
- `quarantine_logging`: Outputting quarantined gem info, default: `true`
- `quarantine_extra_attributes`: Storing custom per-example attributes in the table, default: `nil`
- `quarantine_failsafe_limit`: A failsafe limit of quarantined tests in a single run, default: `10`
- `quarantine_release_at_consecutive_passes`: Releasing a test from quarantine after it records enough consecutive passes (`nil` to disable this feature), default: `nil`

### Databases

Quarantine comes with built-in support for the following database types:
- `:dynamodb`
- `:google_sheets`

To use `:dynamodb`, be sure to add `gem 'aws-sdk-dynamodb', '~> 1', group: :test` to your `Gemfile`.

To use `:google_sheets`, be sure to add `gem 'google_drive', '~> 3', group: :test` to your `Gemfile`. Here's an example:

```rb
config.quarantine_database = {
  type: :google_sheets,
  authorization: {type: :service_account_key, file: "service_account.json"}, # also accepts `type: :config`
  spreadsheet: {
    type: :by_key, # also accepts `type: :by_title` and `type: :by_url`
    key: "1Jb5fC6wSuIMnP85tUR5knuZ4f5fuu4nMzQF6-0l-EXAMPLE"}, # also accepts `type: :by_title` and `type: :by_url`
}
```

The spreadsheet first line (1) should contains: id, full_description, updated_at, last_status, location, extra_attributes, consecutive_passes. Something like:

 A | B                   | C          | D           | E        | F                | G
-- | :-----------------: | :---------:| :----------:| :-------:| :---------------:| :--:
id | full_description    | updated_at | last_status | location | extra_attributes | consecutive_passes


To use a custom database that's not provided, subclass `Quarantine::Databases::Base` and pass an instance of your class as the `quarantine_database` setting:

```rb
class MyDatabase < Quarantine::Databases::Base
  ...
end

RSpec.configure do |config|
  config.quarantine_database = MyDatabase.new(...)
end
```

### Extra attributes

Use `quarantine_extra_attributes` to store custom data with each test in the database, e.g. variables useful for your CI setup.

```rb
 config.quarantine_extra_attributes = Proc.new do |example|
   {
     build_url: ENV['BUILDKITE_BUILD_URL'],
     job_id: ENV['BUILDKITE_JOB_ID'],
   }
 end
```

---

## FAQs

#### Why are quarantined tests not being skipped locally?

Quarantine may be configured to only run in certain environments. Check your `spec_helper.rb`, and make sure you have all necessary environment variables set, e.g.:

```sh
CI=1 BRANCH=master bundle exec rspec
```

#### Why is Quarantine failing to connect to DynamoDB?

The AWS client attempts to loads credentials from the following locations, in order:
- The optional `credentials` field in `RSpec.configuration.quarantine_database`
- `ENV['AWS_ACCESS_KEY_ID']` and `ENV['AWS_SECRET_ACCESS_KEY']`
- `Aws.config[:credentials]`
- The shared credentials ini file at `~/.aws/credentials`

More detailed information can be found in the [AWS SDK documentation](https://docs.aws.amazon.com/sdkforruby/api/Aws/S3/Client.html)

#### Why is `example.clear_exception` failing locally?

`Example#clear_exception` is an attribute added through [RSpec::Retry](https://github.com/NoRedInk/rspec-retry). Make sure it has been installed and configured.
