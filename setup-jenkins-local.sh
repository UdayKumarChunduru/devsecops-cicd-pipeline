#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
step()  { echo ""; echo "=================================================="; echo "STEP: $1"; echo "=================================================="; }

step "starting jenkins and sonarqube containers"
docker compose up -d --build jenkins sonarqube

step "waiting for jenkins to respond"
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login | grep -q 200; then
    pass "jenkins is up"
    break
  fi
  info "waiting, check $i of 30"
  sleep 5
done

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

step "jenkins initial admin password"
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

echo ""
echo "=================================================="
echo "containers running, open http://localhost:8080 to finish setup if this is a fresh jenkins install"
echo "=================================================="
