# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


# ------------------------------------------------------------------------------
# S3 Bucket: Stores raw Gmail emails and structured output
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "gmail_bucket" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "${var.project_name}-bucket"
    Environment = "production"
  }
}

# ------------------------------------------------------------------------------
# DynamoDB Table: Stores structured email results
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "gmail_structured_data" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email_id"

  attribute {
    name = "email_id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-dynamodb"
    Environment = "production"
  }
}

# ------------------------------------------------------------------------------
# Lambda Layer: chardet for email encoding detection
# ------------------------------------------------------------------------------
resource "aws_lambda_layer_version" "chardet_layer" {
  filename            = "lambda/layers/chardet-layer.zip"
  layer_name          = "${var.project_name}-chardet-layer"
  compatible_runtimes = [var.lambda_runtime]
  description         = "Library for email encoding detection"
}

# ------------------------------------------------------------------------------
# IAM Role for ALL Lambda functions
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.project_name}-lambda-exec-role"
  description = "IAM role for Lambda functions in Gmail processing pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-role"
    Environment = "production"
  }
}

# Lambda policy: S3 read/write access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-s3-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.gmail_bucket.arn,
          "${aws_s3_bucket.gmail_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.gmail_bucket.arn}/structured-results/*"
      }
    ]
  })
}

# Lambda policy: DynamoDB write access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-dynamodb-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.gmail_structured_data.arn
      }
    ]
  })
}

# Lambda policy: Invoke Bedrock model
resource "aws_iam_role_policy" "lambda_bedrock_policy" {
  name = "${var.project_name}-bedrock-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}"
      }
    ]
  })
}

# Lambda policy: Start Step Functions execution
resource "aws_iam_role_policy" "lambda_sfn_policy" {
  name = "${var.project_name}-sfn-start-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "states:StartExecution",
          "states:DescribeExecution"
        ],
        Effect   = "Allow",
        Resource = aws_sfn_state_machine.gmail_processing.arn
      }
    ]
  })
}

# Attach managed policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ------------------------------------------------------------------------------
# IAM Role for Step Functions
# ------------------------------------------------------------------------------
resource "aws_iam_role" "step_function_exec_role" {
  name        = "${var.project_name}-sfn-exec-role"
  description = "IAM role for Step Functions to invoke Lambdas"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "step_function_policy" {
  name        = "step-function-gmail-processing-policy"
  description = "Policy for Step Functions to invoke Lambda/Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction",
          "bedrock:InvokeModel",
          "dynamodb:PutItem",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_policy_attach" {
  role       = aws_iam_role.step_function_exec_role.name
  policy_arn = aws_iam_policy.step_function_policy.arn
}
# Step Functions policy: Invoke Lambda functions
resource "aws_iam_role_policy" "sfn_lambda_policy" {
  name = "${var.project_name}-sfn-lambda-policy"
  role = aws_iam_role.step_function_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "lambda:InvokeFunction",
        Effect = "Allow",
        Resource = [
          aws_lambda_function.parse_email.arn,
          aws_lambda_function.invoke_bedrock.arn,
          aws_lambda_function.extract_business.arn,
          aws_lambda_function.save_to_dynamodb.arn
        ]
      }
    ]
  })
}

locals {
  # List all roles that need X-Ray policy
  roles_that_need_xray = [
    aws_iam_role.lambda_exec_role.name,
    aws_iam_role.step_function_exec_role.name
  ]
}
# Add X-Ray permissions to lambda_exec_role (append to existing lambda_s3_policy or create new policy)
resource "aws_iam_role_policy" "lambda_xray_policy" {
  name     = "${var.project_name}-lambda-xray-policy"
  for_each = toset(local.roles_that_need_xray)
  role     = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}


# ------------------------------------------------------------------------------
# Lambda 1: Start Step Functions when file lands in S3
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "start_step_function" {
  filename      = "lambda/start_step_function.zip"
  function_name = "${var.project_name}-start-sfn"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "start_step_function.lambda_handler"
  runtime       = var.lambda_runtime

  tracing_config {
    mode = "Active" # Critical: Enables X-Ray tracing
  }

  environment {
    variables = {
      STEP_FUNCTION_ARN = aws_sfn_state_machine.gmail_processing.arn
    }
  }
}

# ------------------------------------------------------------------------------
# Lambda 2: Parse email (.eml) from S3
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "parse_email" {
  filename      = "lambda/parse_email.zip"
  function_name = "${var.project_name}-parse-email"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "parse_email.lambda_handler"
  runtime       = var.lambda_runtime
  layers        = [aws_lambda_layer_version.chardet_layer.arn]

  tracing_config {
    mode = "Active" # Critical: Enables X-Ray tracing
  }
}

# ------------------------------------------------------------------------------
# Lambda 3: Invoke Bedrock for AI analysis
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "invoke_bedrock" {
  filename      = "lambda/invoke_bedrock.zip"
  function_name = "${var.project_name}-invoke-bedrock"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "invoke_bedrock.lambda_handler"
  runtime       = var.lambda_runtime

  tracing_config {
    mode = "Active" # Critical: Enables X-Ray tracing
  }

  environment {
    variables = {
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
}

# ------------------------------------------------------------------------------
# Lambda 4: Extract business fields (phone, email, order ID, etc.)
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "extract_business" {
  filename      = "lambda/extract_business.zip"
  function_name = "${var.project_name}-extract-business"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "extract_business.lambda_handler"
  runtime       = var.lambda_runtime

  tracing_config {
    mode = "Active" # Critical: Enables X-Ray tracing
  }
}

# ------------------------------------------------------------------------------
# Lambda 5: Save structured data to DynamoDB
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "save_to_dynamodb" {
  filename      = "lambda/save_to_dynamodb.zip"
  function_name = "${var.project_name}-save-to-dynamodb"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "save_to_dynamodb.lambda_handler"
  runtime       = var.lambda_runtime

  tracing_config {
    mode = "Active" # Critical: Enables X-Ray tracing
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
}

# ------------------------------------------------------------------------------
# CloudWatch Log Group for Step Functions
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "step_function_logs" {
  name              = "/aws/stepfunctions/${var.project_name}-state-machine"
  retention_in_days = var.step_function_log_retention
}

# ------------------------------------------------------------------------------
# Shared IAM Policy: Full CloudWatch Access (Testing Only)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Shared IAM Policy: Minimal CloudWatch Logs Access (Least Privilege)
# For Lambda/Step Functions to write logs to CloudWatch
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "shared_cloudwatch_logs_write_policy" {
  name        = "${var.project_name}-shared-cloudwatch-logs-write"
  description = "Minimal policy for writing logs to CloudWatch Logs (Lambda/Step Functions)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWriteAccess"
        Effect = "Allow"
        Action = [
          # Core log writing permissions
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ],
        # Restrict to your project's log groups (least privilege!)
        Resource = [
          "${aws_cloudwatch_log_group.step_function_logs.arn}*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Attach CloudWatch Logs policy to Lambda execution role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.shared_cloudwatch_logs_write_policy.arn
}

# ------------------------------------------------------------------------------
# Attach CloudWatch Logs policy to Step Functions execution role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "sfn_cloudwatch_logs_attach" {
  role       = aws_iam_role.step_function_exec_role.name
  policy_arn = aws_iam_policy.shared_cloudwatch_logs_write_policy.arn
}

# ------------------------------------------------------------------------------
# Step Functions State Machine
# ------------------------------------------------------------------------------
resource "aws_sfn_state_machine" "gmail_processing" {
  name     = "${var.project_name}-state-machine"
  role_arn = aws_iam_role.step_function_exec_role.arn

  tracing_configuration {
    enabled = true # Critical: Enables X-Ray tracing
  }

  definition = templatefile("step_functions/gmail_processing_asl.tpl", {
    parse_email_arn      = aws_lambda_function.parse_email.arn
    invoke_bedrock_arn   = aws_lambda_function.invoke_bedrock.arn
    extract_business_arn = aws_lambda_function.extract_business.arn
    save_to_dynamodb_arn = aws_lambda_function.save_to_dynamodb.arn
  })

  # logging_configuration {
  #   level                  = "ALL"
  #   include_execution_data = true
  #   log_destination        = aws_cloudwatch_log_group.step_function_logs.arn
  # }

}

# ------------------------------------------------------------------------------
# Permission: S3 can invoke Lambda
# ------------------------------------------------------------------------------
resource "aws_lambda_permission" "s3_trigger_lambda" {
  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_step_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.gmail_bucket.arn
}

# ------------------------------------------------------------------------------
# Permission: Step Functions can invoke Lambdas
# ------------------------------------------------------------------------------
resource "aws_lambda_permission" "sfn_invoke_lambda" {
  for_each = {
    parse_email      = aws_lambda_function.parse_email.arn
    invoke_bedrock   = aws_lambda_function.invoke_bedrock.arn
    extract_business = aws_lambda_function.extract_business.arn
    save_to_dynamodb = aws_lambda_function.save_to_dynamodb.arn
  }

  statement_id  = "AllowSFNInvoke${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = split(":", each.value)[6]
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.gmail_processing.arn
}

# ------------------------------------------------------------------------------
# S3 Event Notification: Trigger Lambda on new .eml upload
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "gmail_bucket_notification" {
  bucket = aws_s3_bucket.gmail_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_step_function.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_trigger_lambda]
}
