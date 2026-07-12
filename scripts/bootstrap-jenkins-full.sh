#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "checking env file"
touch .env
if grep -q "^PIPELINE_REPO_PATH=" .env; then
  pass "pipeline_repo_path already set"
else
  echo "PIPELINE_REPO_PATH=$(pwd)" >> .env
  pass "pipeline_repo_path set"
fi
if grep -q "^JENKINS_AGENT_SECRET=" .env; then
  pass "jenkins_agent_secret already set"
else
  echo "JENKINS_AGENT_SECRET=unused" >> .env
fi

bash scripts/generate-jenkins-admin.sh

step "starting sonarqube alone first"
docker compose up -d sonarqube

step "waiting for sonarqube to respond"
for i in $(seq 1 30); do
  STATUS=$(curl -s http://localhost:9000/api/system/status | grep -o '"status":"[A-Z]*"' || echo "")
  if echo "$STATUS" | grep -q "UP"; then
    pass "sonarqube is up"
    break
  fi
  info "waiting, check $i of 30"
  sleep 5
done

bash scripts/bootstrap-sonarqube.sh

step "checking snyk token"
source scripts/lib.sh
SNYK_EXISTING=$(get_env_var SNYK_TOKEN)
if [ -z "$SNYK_EXISTING" ]; then
  echo "snyk token not found in .env"
  read -p "paste snyk token now: " SNYK_VALUE
  set_env_var SNYK_TOKEN "$SNYK_VALUE"
fi
pass "snyk token present"

step "provisioning scoped jenkins iam user"
bash scripts/setup-jenkins-iam.sh

step "building and starting jenkins with casc"
docker compose up -d --build jenkins

step "waiting for jenkins to respond"
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login | grep -q 200; then
    pass "jenkins is up"
    break
  fi
  info "waiting, check $i of 30"
  sleep 5
done

step "jenkins admin credentials"
JENKINS_ADMIN_USER=$(get_env_var JENKINS_ADMIN_USER)
JENKINS_ADMIN_PASSWORD=$(get_env_var JENKINS_ADMIN_PASSWORD)
info "username: $JENKINS_ADMIN_USER"
info "password stored in .env under JENKINS_ADMIN_PASSWORD, not printed here"

echo ""
echo "=================================================="
echo "jenkins ready at http://localhost:8080 with credentials sonar-token snyk-token aws-account-id aws-jenkins-creds already provisioned via casc"
echo "=================================================="
