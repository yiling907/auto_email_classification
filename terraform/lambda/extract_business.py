"""
Lambda Function: Extract Business Entities
Purpose: Use regex to extract structured business data from email body
Complementary to AI analysis (faster, deterministic)
"""
import re


def lambda_handler(event, context):
    """
    Main handler for regex-based entity extraction

    Args:
        event (dict): Input from previous step (contains parsed email + AI analysis)
        context (object): Lambda context object

    Returns:
        dict: Enhanced event with structured business entities
    """
    try:
        # Get email body from input
        email_body = event.get('body_text', '')

        # Define regex patterns for common business entities
        business_entities = {
            # Phone numbers (supports 11-digit mobile + US-style landline)
            'phone_numbers': re.findall(r'\b\d{11}\b|\b\d{3}[-.]\d{3}[-.]\d{4}\b', email_body),

            # Email addresses
            'email_addresses': re.findall(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', email_body),

            # Order IDs (pattern: Order ID: XXX)
            'order_ids': re.findall(r'Order ID[:：]\s*(\w+)', email_body),

            # Monetary amounts (pattern: Amount: 50)
            'amounts': re.findall(r'Amount[:：]\s*(\d+\.?\d*)', email_body),
        }

        # Add business entities to event
        event['business_info'] = business_entities
        return event

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"Business entity extraction failed: {str(e)}")