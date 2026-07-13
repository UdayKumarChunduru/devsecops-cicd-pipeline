#!/usr/bin/env bash

set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Set EKS_CLUSTER_NAME}"
: "${LAMBDA_ROLE_ARN:?Set LAMBDA_ROLE_ARN}"

FUNC_NAME="falco-remediation"
PKG_DIR="lambda-package"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

rm -rf "$PKG_DIR" falco_remediation.zip
mkdir -p "$PKG_DIR"

python3 -m venv venv
venv/bin/pip install kubernetes --target "$PKG_DIR" --quiet
cp "$HERE/falco_remediation.py" "$PKG_DIR/"
(cd "$PKG_DIR" && zip -qr ../falco_remediation.zip .)

if aws lambda get-function --function-name "$FUNC_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNC_NAME" \
    --zip-file fileb://falco_remediation.zip --region "$AWS_REGION"
  aws lambda wait function-updated-v2 --function-name "$FUNC_NAME" --region "$AWS_REGION"
else
  aws lambda create-function --function-name "$FUNC_NAME" \
    --runtime python3.12 --handler falco_remediation.handler \
    --role "$LAMBDA_ROLE_ARN" --timeout 30 --memory-size 256 \
    --zip-file fileb://falco_remediation.zip --region "$AWS_REGION"
  aws lambda wait function-active-v2 --function-name "$FUNC_NAME" --region "$AWS_REGION"
fi

aws lambda update-function-configuration --function-name "$FUNC_NAME" \
  --environment "Variables={EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME},TARGET_NAMESPACE=default}" \
  --region "$AWS_REGION"
aws lambda wait function-updated-v2 --function-name "$FUNC_NAME" --region "$AWS_REGION"

echo "Lambda $FUNC_NAME deployed against $EKS_CLUSTER_NAME. Now run aws/sns/sns-setup.sh."
