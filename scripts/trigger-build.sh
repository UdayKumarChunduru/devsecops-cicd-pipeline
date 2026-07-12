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

JENKINS_ADMIN_USER=$(get_env_var JENKINS_ADMIN_USER)
JENKINS_ADMIN_PASSWORD=$(get_env_var JENKINS_ADMIN_PASSWORD)

COOKIE_JAR=$(mktemp)

CRUMB_JSON=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  "http://localhost:8080/crumbIssuer/api/json")

CRUMB_FIELD=$(echo "$CRUMB_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null) || true
CRUMB=$(echo "$CRUMB_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['crumb'])" 2>/dev/null) || true

if [ -z "$CRUMB" ]; then
  fail "could not get csrf crumb, response was: $CRUMB_JSON"
  rm -f "$COOKIE_JAR"
  exit 1
fi

HTTP_STATUS=$(curl -s -o /tmp/trigger-response.html -w "%{http_code}" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  -H "${CRUMB_FIELD}: ${CRUMB}" \
  -X POST "http://localhost:8080/job/devsecops-pipeline/build")

rm -f "$COOKIE_JAR"

if [ "$HTTP_STATUS" = "201" ]; then
  pass "build triggered, watch progress at http://localhost:8080/job/devsecops-pipeline/"
else
  fail "build trigger failed with http status $HTTP_STATUS"
  cat /tmp/trigger-response.html
  exit 1
fi
