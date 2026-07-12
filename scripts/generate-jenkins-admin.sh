#!/usr/bin/env bash
set -euo pipefail
source scripts/lib.sh

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "jenkins admin user"
JENKINS_ADMIN_USER=$(get_env_var JENKINS_ADMIN_USER)
if [ -z "$JENKINS_ADMIN_USER" ]; then
  set_env_var JENKINS_ADMIN_USER admin
  info "jenkins admin user set to admin"
fi

JENKINS_ADMIN_PASSWORD=$(get_env_var JENKINS_ADMIN_PASSWORD)
if [ -z "$JENKINS_ADMIN_PASSWORD" ]; then
  JENKINS_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
  set_env_var JENKINS_ADMIN_PASSWORD "$JENKINS_ADMIN_PASSWORD"
  info "generated a new jenkins admin password"
else
  info "jenkins admin password already set"
fi
pass "jenkins admin credentials ready in .env"
