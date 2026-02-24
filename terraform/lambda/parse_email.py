"""
Lambda Function: Parse Raw Email (.eml) from S3
Purpose: Extract basic email metadata (sender, subject, body, attachments)
Dependencies: chardet (from Lambda Layer) for encoding detection
"""
import boto3
import email
import chardet
from email.header import decode_header

# Initialize S3 client
s3_client = boto3.client('s3')


def decode_email_header(header_value):
    """
    Decode email headers with non-ASCII characters (e.g., Chinese/Japanese)

    Args:
        header_value (str): Raw header value from email

    Returns:
        str: Decoded header string
    """
    if not header_value:
        return ""

    decoded_parts = decode_header(header_value)
    result_parts = []

    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            if encoding:
                # Decode with specified encoding
                result_parts.append(part.decode(encoding, errors='replace'))
            else:
                # Auto-detect encoding if not specified
                detected_encoding = chardet.detect(part)['encoding']
                result_parts.append(part.decode(detected_encoding, errors='replace'))
        else:
            # Already a string - add directly
            result_parts.append(part)

    return ''.join(result_parts)


def lambda_handler(event, context):
    """
    Main handler for parsing email content from S3

    Args:
        event (dict): Input from Step Functions (contains s3_bucket/s3_key/email_id)
        context (object): Lambda context object

    Returns:
        dict: Enhanced event with parsed email metadata
    """
    try:
        # Extract input parameters from Step Functions
        bucket_name = event['s3_bucket']
        object_key = event['s3_key']
        email_id = event['email_id']

        # Download raw email from S3
        s3_response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        email_data = s3_response['Body'].read()

        # Parse email content using Python's email library
        email_message = email.message_from_bytes(email_data)

        # Extract basic email metadata
        parsed_email = {
            'email_id': email_id,
            'subject': decode_email_header(email_message.get('Subject', '')),
            'sender': decode_email_header(email_message.get('From', '')),
            'recipient': decode_email_header(email_message.get('To', '')),
            'cc': decode_email_header(email_message.get('Cc', '')),
            'date': decode_email_header(email_message.get('Date', '')),
            'attachments': [],
            'body_text': ''
        }

        # Process multipart emails (most common)
        if email_message.is_multipart():
            for part in email_message.walk():
                content_disposition = part.get('Content-Disposition', '')

                # Extract attachments
                if 'attachment' in content_disposition:
                    filename = decode_email_header(part.get_filename())
                    if filename:
                        parsed_email['attachments'].append(filename)

                # Extract plain text body (prioritize over HTML)
                elif part.get_content_type() == 'text/plain':
                    body_payload = part.get_payload(decode=True)
                    detected_encoding = chardet.detect(body_payload)['encoding']
                    parsed_email['body_text'] = body_payload.decode(detected_encoding, errors='replace')

        # Process non-multipart emails (simple text emails)
        else:
            body_payload = email_message.get_payload(decode=True)
            detected_encoding = chardet.detect(body_payload)['encoding']
            parsed_email['body_text'] = body_payload.decode(detected_encoding, errors='replace')

        # Merge parsed data back into event for next Step Functions step
        event.update(parsed_email)
        return event

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"Email parsing failed: {str(e)}")