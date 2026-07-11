#!/usr/bin/env bash

set -euo pipefail

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"
: "${KUBE_API_SERVER:?Set KUBE_API_SERVER}"
: "${KUBE_SA_TOKEN:?Set KUBE_SA_TOKEN}"

FUNC_NAME="falco-remediation"
ROLE_NAME="falco-remediation-role"
PKG_DIR="lambda-package"
HERE="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$PKG_DIR" falco_remediation.zip
mkdir -p "$PKG_DIR"
pip install kubernetes --target "$PKG_DIR" --quiet
cp "$HERE/falco_remediation.py" "$PKG_DIR/"
(cd "$PKG_DIR" && zip -qr ../falco_remediation.zip .)

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "Waiting for role propagation"
  sleep 10
fi

if aws lambda get-function --function-name "$FUNC_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FUNC_NAME" \
    --zip-file fileb://falco_remediation.zip --region "$AWS_REGION"
else
  aws lambda create-function --function-name "$FUNC_NAME" \
    --runtime python3.12 --handler falco_remediation.handler \
    --role "$ROLE_ARN" --timeout 30 --memory-size 256 \
    --zip-file fileb://falco_remediation.zip --region "$AWS_REGION"
fi

aws lambda update-function-configuration --function-name "$FUNC_NAME" \
  --environment "Variables={KUBE_API_SERVER=${KUBE_API_SERVER},KUBE_SA_TOKEN=${KUBE_SA_TOKEN},TARGET_NAMESPACE=default}" \
  --region "$AWS_REGION"

echo "Lambda $FUNC_NAME deployed. Now run aws/sns/sns-setup.sh."
