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
source scripts/lib.sh
EXISTING_IN_ENV=$(get_env_var AWS_JENKINS_ACCESS_KEY_ID)
EXISTING_KEYS=$(aws iam list-access-keys --user-name "$USER_NAME" --query "AccessKeyMetadata[].AccessKeyId" --output text)
if [ -n "$EXISTING_IN_ENV" ] && [ -n "$EXISTING_KEYS" ]; then
  pass "access key already provisioned and saved in .env"
elif [ -n "$EXISTING_KEYS" ] && [ -z "$EXISTING_IN_ENV" ]; then
  info "iam access key exists but is not in .env, deleting and creating a fresh one since the old secret cannot be retrieved"
  for KEY_ID in $EXISTING_KEYS; do
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$KEY_ID"
  done
  KEY_JSON=$(aws iam create-access-key --user-name "$USER_NAME" --output json)
  set_env_var AWS_JENKINS_ACCESS_KEY_ID "$(echo "$KEY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")"
  set_env_var AWS_JENKINS_SECRET_ACCESS_KEY "$(echo "$KEY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")"
  pass "access key created and saved in .env"
else
  KEY_JSON=$(aws iam create-access-key --user-name "$USER_NAME" --output json)
  set_env_var AWS_JENKINS_ACCESS_KEY_ID "$(echo "$KEY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")"
  set_env_var AWS_JENKINS_SECRET_ACCESS_KEY "$(echo "$KEY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")"
  pass "access key created and saved in .env"
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
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "pods"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
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

source scripts/lib.sh
set_env_var AWS_ACCOUNT_ID "$(aws sts get-caller-identity --query Account --output text)"

echo ""
echo "=================================================="
echo "jenkins iam user ready, access key and account id saved to .env, casc will inject them into jenkins credentials on next container start"
echo "=================================================="
