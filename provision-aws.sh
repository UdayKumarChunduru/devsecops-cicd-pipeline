#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="devsecops-real"
AWS_REGION="us-east-1"
ECR_REPO="demo-service"
SNS_TOPIC="devsecops-pipeline-alerts"
LAMBDA_ROLE_NAME="falco-remediation-lambda-role"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "checking prerequisites"
for bin in aws eksctl kubectl helm python3 pip zip; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "$bin found: $(command -v $bin)"
  else
    fail "$bin not found in PATH"
    exit 1
  fi
done

step "checking aws identity"
if CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
  pass "aws credentials valid"
  echo "$CALLER_IDENTITY"
else
  fail "aws sts get-caller-identity failed, run aws configure first"
  exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION
info "account id: $AWS_ACCOUNT_ID"
info "region: $AWS_REGION"

step "eks cluster"
if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  pass "cluster $CLUSTER_NAME already exists, skipping creation"
else
  info "cluster $CLUSTER_NAME not found, creating now, this takes 15-20 minutes"
  eksctl create cluster -f eks/cluster.yaml
  if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    pass "cluster $CLUSTER_NAME created"
  else
    fail "cluster creation did not complete successfully"
    exit 1
  fi
fi

step "kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
if kubectl get nodes >/dev/null 2>&1; then
  pass "kubectl can reach the cluster"
  kubectl get nodes
else
  fail "kubectl cannot reach the cluster after update-kubeconfig"
  exit 1
fi

step "ecr repository"
if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
  pass "ecr repo $ECR_REPO already exists"
else
  aws ecr create-repository \
    --repository-name "$ECR_REPO" \
    --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1; then
    pass "ecr repo $ECR_REPO created"
  else
    fail "ecr repo creation failed"
    exit 1
  fi
fi
info "ecr repo uri: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

step "lambda iam role"
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
  pass "role $LAMBDA_ROLE_NAME already exists"
else
  aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document file://aws/iam/lambda-trust-policy.json >/dev/null
  if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
    pass "role $LAMBDA_ROLE_NAME created"
  else
    fail "role creation failed"
    exit 1
  fi
fi

if aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "AttachedPolicies[?PolicyName=='AWSLambdaBasicExecutionRole']" --output text | grep -q AWSLambdaBasicExecutionRole; then
  pass "basic execution policy already attached"
else
  aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  pass "basic execution policy attached"
fi

aws iam put-role-policy \
  --role-name "$LAMBDA_ROLE_NAME" \
  --policy-name eks-describe-cluster \
  --policy-document file://aws/iam/lambda-eks-permissions.json
pass "eks describe policy applied, put-role-policy is idempotent by design"

export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)
info "lambda role arn: $LAMBDA_ROLE_ARN"

step "aws-auth mapping"
if eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --arn "$LAMBDA_ROLE_ARN" >/dev/null 2>&1; then
  pass "lambda role already mapped in aws-auth"
else
  eksctl create iamidentitymapping \
    --cluster "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --arn "$LAMBDA_ROLE_ARN" \
    --username falco-remediator-lambda \
    --group falco-remediator-group
  if eksctl get iamidentitymapping --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --arn "$LAMBDA_ROLE_ARN" >/dev/null 2>&1; then
    pass "lambda role mapped into aws-auth"
  else
    fail "aws-auth mapping did not take effect"
    exit 1
  fi
fi

step "kubernetes rbac"
kubectl apply -f k8s/rbac-falco-remediator.yaml
if kubectl get role falco-remediator -n default >/dev/null 2>&1 && kubectl get rolebinding falco-remediator-binding -n default >/dev/null 2>&1; then
  pass "role and rolebinding present"
else
  fail "rbac apply did not produce expected objects"
  exit 1
fi

step "helm repos"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null
pass "helm repos added and updated"

step "kyverno"
if helm status kyverno -n kyverno >/dev/null 2>&1; then
  pass "kyverno already installed"
else
  helm install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --timeout 5m
  if helm status kyverno -n kyverno >/dev/null 2>&1; then
    pass "kyverno installed"
  else
    fail "kyverno install failed"
    exit 1
  fi
fi

kubectl apply -f kyverno/
if kubectl get clusterpolicy disallow-root-user >/dev/null 2>&1 && kubectl get clusterpolicy require-resource-limits >/dev/null 2>&1; then
  pass "kyverno policies applied"
else
  fail "kyverno policy apply did not produce expected objects"
  exit 1
fi

step "falcosidekick irsa"
if eksctl get iamserviceaccount --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --namespace falco --name falcosidekick >/dev/null 2>&1; then
  pass "falcosidekick service account already exists"
else
  export EKS_CLUSTER_NAME="$CLUSTER_NAME"
  bash aws/iam/setup-falcosidekick-irsa.sh
  if eksctl get iamserviceaccount --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --namespace falco --name falcosidekick >/dev/null 2>&1; then
    pass "falcosidekick service account created"
  else
    fail "falcosidekick irsa setup failed"
    exit 1
  fi
fi

step "sns topic"
TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC" --region "$AWS_REGION" --query TopicArn --output text)
if [ -n "$TOPIC_ARN" ]; then
  pass "sns topic ready: $TOPIC_ARN"
else
  fail "sns topic creation returned empty arn"
  exit 1
fi

step "falco and falcosidekick"
if helm status falco -n falco >/dev/null 2>&1; then
  info "falco already installed, upgrading with current values"
  helm upgrade falco falcosecurity/falco -n falco \
    -f falco/falcosidekick-values-aws.yaml \
    --set falcosidekick.config.aws.sns.topicarn="$TOPIC_ARN" \
    --set-file customRules."custom-rules\.yaml"=falco/custom-rules.yaml \
    --wait --timeout 5m
else
  helm install falco falcosecurity/falco -n falco --create-namespace \
    -f falco/falcosidekick-values-aws.yaml \
    --set falcosidekick.config.aws.sns.topicarn="$TOPIC_ARN" \
    --set-file customRules."custom-rules\.yaml"=falco/custom-rules.yaml \
    --wait --timeout 5m
fi

if helm status falco -n falco >/dev/null 2>&1; then
  pass "falco installed"
  kubectl get pods -n falco
else
  fail "falco install failed"
  exit 1
fi

step "lambda function"
export EKS_CLUSTER_NAME="$CLUSTER_NAME"
bash aws/lambda/deploy-lambda.sh
if aws lambda get-function --function-name falco-remediation --region "$AWS_REGION" >/dev/null 2>&1; then
  pass "lambda function falco-remediation is live"
else
  fail "lambda deploy did not produce a callable function"
  exit 1
fi

step "sns subscription"
export AWS_ACCOUNT_ID
bash aws/sns/sns-setup.sh
SUB_COUNT=$(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" --query "length(Subscriptions)" --output text)
if [ "$SUB_COUNT" -gt 0 ]; then
  pass "sns subscription count: $SUB_COUNT"
else
  fail "no subscriptions found on topic"
  exit 1
fi

step "final state summary"
echo "cluster nodes:"
kubectl get nodes
echo ""
echo "pods across namespaces:"
kubectl get pods -A
echo ""
echo "kyverno policies:"
kubectl get clusterpolicies
echo ""
echo "ecr repo:"
aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" --query "repositories[0].repositoryUri" --output text
echo ""
echo "lambda function:"
aws lambda get-function --function-name falco-remediation --region "$AWS_REGION" --query "Configuration.[FunctionName,Role,Runtime,LastModified]" --output table
echo ""
echo "sns topic and subscriptions:"
echo "$TOPIC_ARN"
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" --output table

echo ""
echo "=================================================="
echo "provisioning complete"
echo "run eksctl delete cluster -f eks/cluster.yaml when done testing"
echo "=================================================="

step "running end to end quarantine test"
bash test-quarantine.sh
echo "=================================================="
