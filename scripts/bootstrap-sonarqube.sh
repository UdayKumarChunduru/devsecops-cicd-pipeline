#!/usr/bin/env bash
set -euo pipefail
source scripts/lib.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "sonarqube admin password"
SONAR_ADMIN_PASSWORD=$(get_env_var SONAR_ADMIN_PASSWORD)
if [ -z "$SONAR_ADMIN_PASSWORD" ]; then
  SONAR_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
  set_env_var SONAR_ADMIN_PASSWORD "$SONAR_ADMIN_PASSWORD"
  info "generated a new sonarqube admin password"
fi

step "checking sonarqube admin credential state"
LOGIN_CHECK=$(curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" http://localhost:9000/api/authentication/validate)
if echo "$LOGIN_CHECK" | grep -q '"valid":true'; then
  pass "admin password already set correctly, skipping change"
else
  info "default admin credentials still active, changing password now"
  curl -s -u admin:admin -X POST "http://localhost:9000/api/users/change_password" \
    -d "login=admin&previousPassword=admin&password=${SONAR_ADMIN_PASSWORD}" >/dev/null
  CONFIRM=$(curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" http://localhost:9000/api/authentication/validate)
  if echo "$CONFIRM" | grep -q '"valid":true'; then
    pass "admin password changed"
  else
    fail "password change did not take effect"
    exit 1
  fi
fi

step "sonarqube token for jenkins"
curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST "http://localhost:9000/api/user_tokens/revoke" \
  -d "name=jenkins" >/dev/null || true

TOKEN_RESPONSE=$(curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST "http://localhost:9000/api/user_tokens/generate" \
  -d "name=jenkins")

SONAR_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)['token'])
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
  fail "token generation failed, response was: $TOKEN_RESPONSE"
  exit 1
}
if [ -z "$SONAR_TOKEN" ]; then
  fail "token generation did not return a token"
  exit 1
fi
set_env_var SONAR_TOKEN "$SONAR_TOKEN"
pass "sonar token generated and saved"

step "sonarqube webhook for jenkins"
EXISTING_WEBHOOKS=$(curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" "http://localhost:9000/api/webhooks/list")
if echo "$EXISTING_WEBHOOKS" | grep -q '"name":"jenkins"'; then
  pass "jenkins webhook already exists"
else
  curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST "http://localhost:9000/api/webhooks/create" \
    -d "name=jenkins&url=http://jenkins:8080/sonarqube-webhook/" >/dev/null
  pass "jenkins webhook created"
fi
