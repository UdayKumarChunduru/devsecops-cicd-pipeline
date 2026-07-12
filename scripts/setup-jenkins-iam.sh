#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

AWS_REGION="us-east-1"
CLUSTER_NAME="devsecops-real"
USER_NAME="jenkins-devsecops-pipeline"
POLICY_NAME="jenkins-ecr-eks-scoped"

step "iam user"
if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  pass "user $USER_NAME already exists"
else
  aws iam create-user --user-name "$USER_NAME" >/dev/null
  pass "user $USER_NAME created"
fi

step "iam policy"
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)
if [ -n "$POLICY_ARN" ]; then
  pass "policy $POLICY_NAME already exists"
else
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file://aws/iam/jenkins-ecr-eks-policy.json \
    --query 'Policy.Arn' --output text)
  pass "policy $POLICY_NAME created"
fi
info "policy arn: $POLICY_ARN"

step "attach policy"
ALREADY_ATTACHED=$(aws iam list-attached-user-policies --user-name "$USER_NAME" --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" --output text)
if [ -n "$ALREADY_ATTACHED" ]; then
  pass "policy already attached to user"
else
  aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"
  pass "policy attached to user"
fi

step "access key"
EXISTING_KEYS=$(aws iam list-access-keys --user-name "$USER_NAME" --query "AccessKeyMetadata[].AccessKeyId" --output text)
if [ -n "$EXISTING_KEYS" ]; then
  info "user already has an access key, skipping creation"
  info "existing key ids: $EXISTING_KEYS"
  info "if you need the secret again it cannot be retrieved, delete the old key and rerun this script to get a fresh one"
else
  aws iam create-access-key --user-name "$USER_NAME" --output json > /tmp/jenkins-iam-key.json
  pass "access key created, printed once below, save it now"
  cat /tmp/jenkins-iam-key.json
  rm -f /tmp/jenkins-iam-key.json
fi

step "eks aws-auth mapping"
if eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):user/$USER_NAME" >/dev/null 2>&1; then
  pass "jenkins user already mapped in aws-auth"
else
  eksctl create iamidentitymapping \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):user/$USER_NAME" \
    --username jenkins-deploy \
    --group jenkins-deploy-group
  pass "jenkins user mapped into aws-auth"
fi

step "kubernetes rbac for jenkins deploy"
cat << YAML | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-deploy
  namespace: default
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "pods"]
    verbs: ["get", "list", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-deploy-binding
  namespace: default
subjects:
  - kind: Group
    name: jenkins-deploy-group
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: jenkins-deploy
  apiGroup: rbac.authorization.k8s.io
YAML
pass "jenkins deploy role and binding applied"

echo ""
echo "=================================================="
echo "jenkins iam user ready, use the printed access key and secret for the aws-jenkins-creds credential in jenkins"
echo "account id for the aws-account-id credential: $(aws sts get-caller-identity --query Account --output text)"
echo "=================================================="
