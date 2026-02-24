{
  "Comment": "Gmail email processing workflow: parse, AI analyze, extract, save",
  "StartAt": "ParseEmailBasicInfo",
  "States": {
    "ParseEmailBasicInfo": {
      "Type": "Task",
      "Resource": "${parse_email_arn}",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessFailure"
        }
      ],
      "Next": "InvokeBedrockModel"
    },
    "InvokeBedrockModel": {
      "Type": "Task",
      "Resource": "${invoke_bedrock_arn}",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 3,
          "MaxAttempts": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessFailure"
        }
      ],
      "Next": "ExtractBusinessInfo"
    },
    "ExtractBusinessInfo": {
      "Type": "Task",
      "Resource": "${extract_business_arn}",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessFailure"
        }
      ],
      "Next": "SaveToDynamoDB"
    },
    "SaveToDynamoDB": {
      "Type": "Task",
      "Resource": "${save_to_dynamodb_arn}",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessFailure"
        }
      ],
      "Next": "ProcessSuccess"
    },
    "ProcessSuccess": {
      "Type": "Succeed",
      "Comment": "Email processing completed successfully"
    },
    "ProcessFailure": {
      "Type": "Fail",
      "Error": "ProcessingFailed",
      "Cause": "Workflow failed at one or more steps"
    }
  }
}