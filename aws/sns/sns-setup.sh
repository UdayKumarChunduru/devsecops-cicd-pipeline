#!/usr/bin/env bash

set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"

TOPIC_NAME="devsecops-pipeline-alerts"
LAMBDA_NAME="falco-remediation"

TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --region "$AWS_REGION" \
  --query 'TopicArn' --output text)
echo "Topic: $TOPIC_ARN"

LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_NAME}"

aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id sns-invoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn "$TOPIC_ARN" \
  --region "$AWS_REGION" 2>/dev/null || echo "Invoke permission already present"

aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol lambda \
  --notification-endpoint "$LAMBDA_ARN" \
  --region "$AWS_REGION"

echo "Done. Put $TOPIC_ARN into falco/falcosidekick-values.yaml."
