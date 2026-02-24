"""
Lambda Function: Save Structured Data to DynamoDB
Purpose: Persist all processed email data to DynamoDB for later querying
"""
import boto3
import json
import os
from datetime import datetime

# Initialize DynamoDB resource
dynamodb_resource = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb_resource.Table(os.getenv('DYNAMODB_TABLE_NAME'))


def lambda_handler(event, context):
    """
    Main handler for saving data to DynamoDB

    Args:
        event (dict): Input from previous step (all processed data)
        context (object): Lambda context object

    Returns:
        dict: Success status and email ID
    """
    try:
        # Prepare DynamoDB item (limit text fields to 4000 chars for DynamoDB)
        dynamodb_item = {
            'email_id': event['email_id'],
            'subject': event.get('subject', '')[:4000],
            'sender': event.get('sender', '')[:4000],
            'recipient': event.get('recipient', '')[:4000],
            'date': event.get('date', '')[:4000],
            'body_text': event.get('body_text', '')[:4000],
            'attachments': json.dumps(event.get('attachments', [])),
            'ai_analysis': event.get('ai_analysis', '')[:4000],
            'business_info': json.dumps(event.get('business_info', {})),
            'processed_at': datetime.utcnow().isoformat(),  # UTC timestamp
            'lambda_request_id': context.aws_request_id
        }

        # Write item to DynamoDB
        table.put_item(
            Item=dynamodb_item,
            ConditionExpression='attribute_not_exists(email_id)'  # Prevent overwrites
        )

        # Return success response
        return {
            'status': 'success',
            'email_id': event['email_id'],
            'message': 'Structured email data saved to DynamoDB',
            'processed_at': dynamodb_item['processed_at']
        }

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"DynamoDB save failed: {str(e)}")