#!/usr/bin/env bash

set -euo pipefail

: "${EKS_CLUSTER_NAME:?Set EKS_CLUSTER_NAME}"
: "${AWS_REGION:?Set AWS_REGION}"

eksctl create iamserviceaccount \
  --cluster "$EKS_CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace falco \
  --name falcosidekick \
  --attach-policy-arn "$(aws iam create-policy \
      --policy-name falcosidekick-sns-publish \
      --policy-document file://aws/iam/falcosidekick-irsa-policy.json \
      --query 'Policy.Arn' --output text)" \
  --approve

echo "falcosidekick ServiceAccount created with IRSA role in namespace 'falco'."
