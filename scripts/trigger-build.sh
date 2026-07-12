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

CRUMB=$(curl -s -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  "http://localhost:8080/crumbIssuer/api/json" | python3 -c "import sys,json;print(json.load(sys.stdin)['crumb'])")

if [ -z "$CRUMB" ]; then
  fail "could not get csrf crumb, is jenkins up and are admin credentials correct"
  exit 1
fi

curl -s -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
  -H "Jenkins-Crumb:${CRUMB}" \
  -X POST "http://localhost:8080/job/devsecops-pipeline/build"

pass "build triggered, watch progress at http://localhost:8080/job/devsecops-pipeline/"
