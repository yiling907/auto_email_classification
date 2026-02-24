# S3 outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for emails"
  value       = aws_s3_bucket.gmail_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.gmail_bucket.arn
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "DynamoDB table for structured data"
  value       = aws_dynamodb_table.gmail_structured_data.name
}

# Lambda ARNs
output "lambda_arns" {
  description = "ARN of each Lambda function"
  value = {
    start_step_function = aws_lambda_function.start_step_function.arn
    parse_email         = aws_lambda_function.parse_email.arn
    invoke_bedrock      = aws_lambda_function.invoke_bedrock.arn
    extract_business    = aws_lambda_function.extract_business.arn
    save_to_dynamodb    = aws_lambda_function.save_to_dynamodb.arn
  }
}

# Step Functions output
output "step_function_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.gmail_processing.arn
}

# IAM Roles
output "lambda_exec_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "step_function_exec_role_arn" {
  description = "Step Functions execution role ARN"
  value       = aws_iam_role.step_function_exec_role.arn
}