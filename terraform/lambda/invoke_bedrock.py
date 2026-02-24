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

        # -------------------------- 改动1：适配Llama的Prompt格式 --------------------------
        # Llama 推荐使用 [INST] 标签包裹指令，格式更简洁（保持分析逻辑不变）
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

        # -------------------------- 改动2：Llama的请求Payload格式（核心差异） --------------------------
        # Llama 无需 anthropic_version，参数为 max_gen_len/temperature/top_p 等
        bedrock_payload = json.dumps({
            "prompt": analysis_prompt,          # Llama 核心参数：提示词
            "max_gen_len": 500,                 # 对应 Claude 的 max_tokens
            "temperature": 0.1,                 # 低随机性保证结果稳定
            "top_p": 0.9                       # Llama 必选参数（采样策略）
        })

        # -------------------------- 改动3：调用Llama模型（需配置环境变量 BEDROCK_MODEL_ID） --------------------------
        # 推荐模型ID：meta.llama3-70b-instruct-v1:0（Llama 3 70B）或 meta.llama3-8b-instruct-v1:0（轻量版）
        bedrock_response = bedrock_client.invoke_model(
            modelId=os.getenv('BEDROCK_MODEL_ID', 'meta.llama3-70b-instruct-v1:0'),  # 兜底默认值
            contentType="application/json",
            accept="application/json",
            body=bedrock_payload
        )

        # -------------------------- 改动4：解析Llama的响应（核心差异） --------------------------
        # Llama 响应格式：{"generation": "分析结果文本"}，而非 Claude 的 content 数组
        response_body = json.loads(bedrock_response['body'].read())
        ai_analysis = response_body['generation'].strip()  # 提取生成结果并去除首尾空格

        # Add AI results to event
        event['ai_analysis'] = ai_analysis
        return event

    except Exception as e:
        # Raise error to trigger Step Functions catch logic
        raise Exception(f"Bedrock AI analysis failed: {str(e)}")