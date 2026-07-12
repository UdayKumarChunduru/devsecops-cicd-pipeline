#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="us-east-1"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "checking for a running demo-service pod"
if ! kubectl get deployment demo-service -n default >/dev/null 2>&1; then
  info "demo-service deployment not found, deploying it now with a placeholder image"
  info "no image has been pushed to ecr yet on this branch, using nginx as a stand in target for this test"
  info "spec includes runAsNonRoot and resource limits to satisfy kyverno policies"
  cat << YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-service
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-service
  template:
    metadata:
      labels:
        app: demo-service
        quarantine: "false"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
      containers:
        - name: demo-service
          image: nginxinc/nginx-unprivileged:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
YAML
  kubectl rollout status deployment/demo-service -n default --timeout=120s
fi

TARGET_POD=$(kubectl get pods -n default -l app=demo-service -o jsonpath='{.items[0].metadata.name}')
if [ -z "$TARGET_POD" ]; then
  fail "no demo-service pod found to target"
  exit 1
fi
pass "target pod: $TARGET_POD"

step "publishing a simulated critical falco alert to sns"
TOPIC_ARN=$(aws sns list-topics --region "$AWS_REGION" --query "Topics[?contains(TopicArn,'devsecops-pipeline-alerts')].TopicArn" --output text)
if [ -z "$TOPIC_ARN" ]; then
  fail "sns topic not found"
  exit 1
fi
info "topic: $TOPIC_ARN"

MESSAGE=$(cat << JSON
{"priority": "Critical", "rule": "Privilege Escalation In Demo Container", "output_fields": {"k8s.pod.name": "$TARGET_POD", "k8s.ns.name": "default"}}
JSON
)

aws sns publish --topic-arn "$TOPIC_ARN" --message "$MESSAGE" --region "$AWS_REGION" >/dev/null
pass "alert published for pod $TARGET_POD"

step "watching for the pod to be terminated and replaced"
info "waiting up to 60 seconds"
for i in $(seq 1 12); do
  sleep 5
  STILL_EXISTS=$(kubectl get pod "$TARGET_POD" -n default --ignore-not-found -o name)
  if [ -z "$STILL_EXISTS" ]; then
    pass "pod $TARGET_POD no longer exists, deleted by the lambda"
    break
  fi
  info "still waiting, check $i of 12"
done

if [ -n "$STILL_EXISTS" ]; then
  fail "pod $TARGET_POD still exists after 60 seconds, remediation did not trigger"
  info "checking lambda logs for errors"
  aws logs tail /aws/lambda/falco-remediation --since 5m --region "$AWS_REGION" || true
  exit 1
fi

step "confirming replacement pod is running"
sleep 5
kubectl get pods -n default -l app=demo-service

RUNNING_COUNT=$(kubectl get pods -n default -l app=demo-service --field-selector=status.phase=Running -o name | wc -l)
if [ "$RUNNING_COUNT" -ge 1 ]; then
  pass "replacement pod is running, replicaset controller replaced it automatically"
else
  fail "no running replacement pod found yet, may still be starting"
fi

step "checking lambda invocation logs"
aws logs tail /aws/lambda/falco-remediation --since 5m --region "$AWS_REGION"

echo ""
echo "=================================================="
echo "quarantine test complete"
echo "=================================================="
