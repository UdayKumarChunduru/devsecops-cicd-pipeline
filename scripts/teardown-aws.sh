#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="devsecops-real"
AWS_REGION="us-east-1"
ECR_REPO="demo-service"
SNS_TOPIC="devsecops-pipeline-alerts"
LAMBDA_ROLE_NAME="falco-remediation-lambda-role"
JENKINS_IAM_USER="jenkins-devsecops-pipeline"
JENKINS_IAM_POLICY="jenkins-ecr-eks-scoped"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

if [ -n "${VIRTUAL_ENV:-}" ]; then
  info "Python virtual environment detected: $VIRTUAL_ENV"
  deactivate
  pass "python virtual environment deactivated"
else
  info "no python virtual environment active"
fi

step "local docker containers"
docker compose down -v 2>/dev/null || true
pass "jenkins and sonarqube containers and volumes removed"

step "eks cluster, nodegroup, vpc, oidc provider"
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  eksctl delete cluster -f eks/cluster.yaml
  pass "eks cluster deleted"
else
  info "eks cluster already gone, skipping"
fi

step "lambda function"
if aws lambda get-function --function-name falco-remediation --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda delete-function --function-name falco-remediation --region "$AWS_REGION"
  pass "lambda function deleted"
else
  info "lambda function already gone, skipping"
fi

step "sns subscriptions and topic"
TOPIC_ARN=$(aws sns list-topics --region "$AWS_REGION" --query "Topics[?contains(TopicArn,'${SNS_TOPIC}')].TopicArn" --output text)
if [ -n "$TOPIC_ARN" ]; then
  SUBS=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" --query "Subscriptions[].SubscriptionArn" --output text)
  for SUB in $SUBS; do
    if [ "$SUB" != "PendingConfirmation" ]; then
      aws sns unsubscribe --subscription-arn "$SUB" --region "$AWS_REGION"
    fi
  done
  aws sns delete-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION"
  pass "sns topic and subscriptions deleted"
else
  info "sns topic already gone, skipping"
fi

step "ecr repository"
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr delete-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" --force
  pass "ecr repo and all images deleted"
else
  info "ecr repo already gone, skipping"
fi

step "lambda iam role"
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
  aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name eks-describe-cluster 2>/dev/null || true
  ATTACHED=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "AttachedPolicies[].PolicyArn" --output text)
  for POLICY_ARN in $ATTACHED; do
    aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$POLICY_ARN"
  done
  aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
  pass "lambda iam role deleted"
else
  info "lambda iam role already gone, skipping"
fi

step "jenkins iam user"
if aws iam get-user --user-name "$JENKINS_IAM_USER" >/dev/null 2>&1; then
  KEYS=$(aws iam list-access-keys --user-name "$JENKINS_IAM_USER" --query "AccessKeyMetadata[].AccessKeyId" --output text)
  for KEY_ID in $KEYS; do
    aws iam delete-access-key --user-name "$JENKINS_IAM_USER" --access-key-id "$KEY_ID"
  done
  ATTACHED=$(aws iam list-attached-user-policies --user-name "$JENKINS_IAM_USER" --query "AttachedPolicies[].PolicyArn" --output text)
  for POLICY_ARN in $ATTACHED; do
    aws iam detach-user-policy --user-name "$JENKINS_IAM_USER" --policy-arn "$POLICY_ARN"
  done
  aws iam delete-user --user-name "$JENKINS_IAM_USER"
  pass "jenkins iam user deleted"
else
  info "jenkins iam user already gone, skipping"
fi

step "jenkins iam policy"
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${JENKINS_IAM_POLICY}'].Arn" --output text)
if [ -n "$POLICY_ARN" ]; then
  aws iam delete-policy --policy-arn "$POLICY_ARN"
  pass "jenkins iam policy deleted"
else
  info "jenkins iam policy already gone, skipping"
fi

step "falcosidekick irsa iam policy"
FSK_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='falcosidekick-sns-publish'].Arn" --output text)
if [ -n "$FSK_POLICY_ARN" ]; then
  aws iam delete-policy --policy-arn "$FSK_POLICY_ARN" 2>/dev/null || info "falcosidekick policy still attached elsewhere or already gone, check manually if this matters"
else
  info "falcosidekick irsa policy already gone, skipping"
fi

step "local build artifacts"
rm -rf lambda-package
find aws/lambda/ -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
rm -rf aws/lambda/lambda-package
rm -f aws/lambda/falco_remediation.zip
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find . -name "sbom-*.json" -delete 2>/dev/null || true
find . -name "gitleaks-report.json" -delete 2>/dev/null || true
pass "local build artifacts removed: lambda package, venv, pycache, pytest cache, sbom files, gitleaks report"

step "local env file secrets"
if [ -f .env ]; then
  sed -i '/^AWS_JENKINS_ACCESS_KEY_ID=/d; /^AWS_JENKINS_SECRET_ACCESS_KEY=/d; /^SONAR_TOKEN=/d; /^SONAR_ADMIN_PASSWORD=/d; /^JENKINS_ADMIN_PASSWORD=/d; /^AWS_ACCOUNT_ID=/d' .env
  pass "sensitive generated credentials removed from .env, user-provided values and non-sensitive configuration retained"
fi

echo ""
echo "=================================================="
echo "teardown complete, verify no unexpected billing with:"
echo "aws eks list-clusters --region $AWS_REGION"
echo "aws ecr describe-repositories --region $AWS_REGION"
echo "aws lambda list-functions --region $AWS_REGION"
echo "=================================================="
