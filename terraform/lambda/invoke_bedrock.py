"""
Lambda Function: Invoke AWS Bedrock for AI Email Analysis
Purpose: Use Claude 3 to extract structured insights from email body
Requires: Bedrock access permissions in IAM role
"""
import boto3
import json
import os

# Initialize Bedrock Runtime client
bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')


def lambda_handler(event, context):
    """
    Main handler for AI analysis with Bedrock

    Args:
        event (dict): Input from previous step (contains parsed email data)
        context (object): Lambda context object

    Returns:
        dict: Enhanced event with AI analysis results
    """
    try:
        # Get email body from input (fail fast if empty)
        email_body = event.get('body_text', '')
        if not email_body or len(email_body) < 10:
            raise Exception("Email body is empty or too short for AI analysis")

        # Define prompt for Claude 3 (structured output requirements)
        analysis_prompt = f"""
        Analyze the following email content and return structured insights:
        1. Core Request (max 50 words): What is the sender asking for?
        2. Email Type (one of: Inquiry, Complaint, Refund, Advertising, Other)
        3. Key Entities: Extract phone numbers, email addresses, order IDs, amounts

        Email Content:
        {email_body[:2000]}  # Limit input length to avoid token limits
        """

        # Prepare Bedrock request payload (Claude 3 format)
        bedrock_payload = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 500,
            "temperature": 0.1,  # Low temperature for consistent results
            "messages": [
                {
                    "role": "user",
                    "content": [{"type": "text", "text": analysis_prompt}]
                }
            ]
        })

        # Invoke Bedrock model
        bedrock_response = bedrock_client.invoke_model(
            modelId=os.getenv('BEDROCK_MODEL_ID'),
            contentType="application/json",
            accept="application/json",
            body=bedrock_payload
        )

        # Parse Bedrock response
        response_body = json.loads(bedrock_response['body'].read())
        ai_analysis = response_body['content'][0]['text']

        # Add AI results to event
        event['ai_analysis'] = ai_analysis
        return event

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"Bedrock AI analysis failed: {str(e)}")