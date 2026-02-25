"""
Lambda Function: Invoke AWS Bedrock for AI Email Analysis
Purpose: Use Llama 3 to extract structured insights from email body
Requires: Bedrock access permissions in IAM role (仅需 bedrock:InvokeModel，无需Marketplace权限)
"""
import boto3
import json
import os

# Initialize Bedrock Runtime client
bedrock_client = boto3.client('bedrock-runtime', region_name='us-east-1')


def lambda_handler(event, context):
    """
    Main handler for AI analysis with Bedrock (Llama 3 适配版)

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



        analysis_prompt = f"""
        [INST]
        Analyze the following email content and return structured insights in plain text (follow the exact format):
        1. Core Request (max 50 words): What is the sender asking for?
        2. Email Type (one of: Inquiry, Complaint, Refund, Advertising, Other)
        3. Key Entities: Extract phone numbers, email addresses, order IDs, amounts

        Email Content:
        {email_body[:2000]}  # Limit input length to avoid token limits
        [/INST]
        """



        bedrock_payload = json.dumps({
            "prompt": analysis_prompt,
            "max_gen_len": 500,
            "temperature": 0.1,
            "top_p": 0.9
        })



        bedrock_response = bedrock_client.invoke_model(
            modelId=os.getenv('BEDROCK_MODEL_ID', 'meta.llama3-70b-instruct-v1:0'),
            contentType="application/json",
            accept="application/json",
            body=bedrock_payload
        )



        response_body = json.loads(bedrock_response['body'].read())
        ai_analysis = response_body['generation'].strip()

        # Add AI results to event
        event['ai_analysis'] = ai_analysis
        return event

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"Bedrock AI analysis failed: {str(e)}")