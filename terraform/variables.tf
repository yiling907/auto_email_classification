# AWS region for deployment
variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

# Project naming prefix
variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
  default     = "gmail-processing"
}

# S3 bucket for raw emails and structured results
variable "s3_bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

# DynamoDB table for structured email data
variable "dynamodb_table_name" {
  description = "DynamoDB table to store structured email metadata"
  type        = string
  default     = "GmailStructuredData"
}

# Bedrock model for email analysis
variable "bedrock_model_id" {
  description = "Bedrock foundation model ID for email analysis"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

# Lambda runtime
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.11"
}

# Step Functions log retention
variable "step_function_log_retention" {
  description = "CloudWatch log retention days for Step Functions"
  type        = number
  default     = 30
}