### 1.0.7
Support `it_behaves_like` behavior

### 1.0.6
Update DynamoDB batch_write_item implementation to check for duplicates based on different keys before uploading

### 1.0.5
Add aws_credentials argument during dynamodb initialization to override the AWS SDK credential chain

### 1.0.4
Enable upstream callers to mark an example as flaky through the example's metadata

### 1.0.3
Only require dynamodb instead of full aws-sdk

### 1.0.2
Relax Aws gem version constraint as aws-sdk v3 is 100% backwards compatible with v2

### 1.0.1
Initial Release
