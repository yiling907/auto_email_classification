"""
Lambda Function: Start Step Functions Execution
Trigger: S3 Object Created event (new email in raw-emails/)
Purpose: Extract S3 event details and start Step Functions workflow
"""
import boto3
import json
import os

# Initialize Step Functions client
sfn_client = boto3.client('stepfunctions', region_name='us-east-1')


def lambda_handler(event, context):
    """
    Main handler for starting Step Functions execution

    Args:
        event (dict): S3 event payload (contains bucket/key info)
        context (object): Lambda context object

    Returns:
        dict: HTTP response with execution ARN and status
    """
    try:
        # Extract S3 bucket and object key from event
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        object_key = s3_event['object']['key']

        # Extract email ID from object key (e.g., raw-emails/2026/2/24/12345.eml → 12345)
        email_id = object_key.split('/')[-1].replace('.eml', '')

        # Start Step Functions execution with input parameters
        execution_response = sfn_client.start_execution(
            stateMachineArn=os.getenv('STEP_FUNCTION_ARN'),
            input=json.dumps({
                's3_bucket': bucket_name,
                's3_key': object_key,
                'email_id': email_id
            })
        )

        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Step Functions execution started successfully',
                'execution_arn': execution_response['executionArn'],
                'email_id': email_id
            })
        }

    except Exception as e:
        # Return error response with details
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to start Step Functions execution',
                'details': str(e)
            })
        }