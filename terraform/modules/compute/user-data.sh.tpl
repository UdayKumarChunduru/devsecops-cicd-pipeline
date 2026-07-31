#!/bin/bash
exec > >(tee -a /var/log/user-data.log | tee /dev/console) 2>&1
set -euo pipefail
set -x

trap 'echo "line $LINENO exited with status $?" > /opt/devsecops/bootstrap-failed 2>/dev/null || (mkdir -p /opt/devsecops && echo "line $LINENO exited with status $?" > /opt/devsecops/bootstrap-failed)' ERR

dnf install -y docker amazon-efs-utils awscli git
systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user
usermod -aG docker ssm-user || true

sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" >> /etc/sysctl.conf

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v5.3.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

curl -SL https://github.com/docker/buildx/releases/download/v0.36.0/buildx-v0.36.0.linux-amd64 -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

while [ ! -S /var/run/docker.sock ]; do
  sleep 2
done

mkdir -p /mnt/jenkins_home /mnt/sonarqube_data /mnt/maven_repo

mount -t efs -o tls ${efs_jenkins_id}:/ /mnt/jenkins_home
mount -t efs -o tls ${efs_sonarqube_id}:/ /mnt/sonarqube_data
mount -t efs -o tls ${efs_maven_id}:/ /mnt/maven_repo

echo "${efs_jenkins_id}:/ /mnt/jenkins_home efs _netdev,tls 0 0" >> /etc/fstab
echo "${efs_sonarqube_id}:/ /mnt/sonarqube_data efs _netdev,tls 0 0" >> /etc/fstab
echo "${efs_maven_id}:/ /mnt/maven_repo efs _netdev,tls 0 0" >> /etc/fstab

chown -R 1000:1000 /mnt/sonarqube_data
chmod -R 777 /mnt/jenkins_home /mnt/sonarqube_data /mnt/maven_repo

mkdir -p /opt/devsecops
cd /opt/devsecops
git clone --branch terraform-aws-cloud --depth 1 https://github.com/UdayKumarChunduru/devsecops-cicd-pipeline.git repo

# Helper function to retry reading secrets while IAM permissions propagate
get_secret() {
  local secret_id="$1"
  for i in $(seq 1 12); do
    local val
    if val=$(aws secretsmanager get-secret-value --secret-id "$secret_id" --region "${aws_region}" --query SecretString --output text 2>/dev/null); then
      echo "$val"
      return 0
    fi
    echo "Waiting for IAM policy propagation to read $secret_id (attempt $i/12)..." >&2
    sleep 5
  done
  echo "Failed to read secret $secret_id after 12 attempts" >&2
  return 1
}

JENKINS_ADMIN_USER=$(get_secret "devsecops-pipeline/jenkins-admin-user")
JENKINS_ADMIN_PASSWORD=$(get_secret "devsecops-pipeline/jenkins-admin-password")
SONAR_ADMIN_PASSWORD=$(get_secret "devsecops-pipeline/sonar-admin-password")
SNYK_TOKEN=$(get_secret "devsecops-pipeline/snyk-token")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Retrieve EC2 Private IP to bypass SonarQube loopback webhook restrictions
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
if [ -n "$TOKEN" ]; then
  EC2_PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
else
  EC2_PRIVATE_IP=$(hostname -i | awk '{print $1}')
fi

cat > /opt/devsecops/docker-compose.yml << 'COMPOSEEOF'
services:
  jenkins:
    build:
      context: /opt/devsecops/repo
      dockerfile: Dockerfile.jenkins
    image: jenkins-devsecops:lts-jdk21
    container_name: jenkins
    network_mode: "host"
    user: root
    mem_limit: 3g
    cpus: 2.0
    environment:
      - JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true -Djenkins.install.runSetupWizard=false
      - CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
    volumes:
      - /mnt/jenkins_home:/var/jenkins_home
      - /mnt/maven_repo:/var/jenkins_home/.m2/repository
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/devsecops/repo:/var/jenkins_home/devsecops-cicd-pipeline:ro
      - /opt/devsecops/casc.yaml:/var/jenkins_home/casc.yaml:ro
    restart: unless-stopped

  sonarqube:
    image: sonarqube:26.3.0.120487-community
    container_name: sonarqube
    mem_limit: 2g
    cpus: 1.5
    ports:
      - "9000:9000"
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
      - SONAR_WEB_CONTEXT=/sonarqube
    volumes:
      - /mnt/sonarqube_data:/opt/sonarqube/data
    restart: unless-stopped
COMPOSEEOF

cat > /opt/devsecops/casc.yaml << 'CASCEOF'
jenkins:
  systemMessage: devsecops pipeline controller
  numExecutors: 2
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "JENKINS_USER_PLACEHOLDER"
          password: "JENKINS_PASSWORD_PLACEHOLDER"
  authorizationStrategy:
    globalMatrix:
      entries:
        - user:
            name: "JENKINS_USER_PLACEHOLDER"
            permissions:
              - "Overall/Administer"
        - group:
            name: "authenticated"
            permissions:
              - "Overall/Read"

unclassified:
  location:
    adminAddress: devsecops-pipeline@local
    url: http://127.0.0.1:8080/
  sonarGlobalConfiguration:
    buildWrapperEnabled: true
    installations:
      - name: SonarQube
        serverUrl: http://127.0.0.1:9000/sonarqube
        credentialsId: sonar-token

credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: sonar-token
              secret: "SONAR_TOKEN_PLACEHOLDER"
              description: sonar-token
          - string:
              scope: GLOBAL
              id: snyk-token
              secret: "SNYK_TOKEN_PLACEHOLDER"
              description: snyk-token
          - string:
              scope: GLOBAL
              id: aws-account-id
              secret: "AWS_ACCOUNT_ID_PLACEHOLDER"
              description: aws-account-id

jobs:
  - script: |
      pipelineJob('devsecops-pipeline') {
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url('https://github.com/UdayKumarChunduru/devsecops-cicd-pipeline.git')
                }
                branch('*/terraform-aws-cloud')
              }
            }
            scriptPath('Jenkinsfile')
          }
        }
      }
CASCEOF

sed -i "s#JENKINS_USER_PLACEHOLDER#$JENKINS_ADMIN_USER#g; s#JENKINS_PASSWORD_PLACEHOLDER#$JENKINS_ADMIN_PASSWORD#g; s#SNYK_TOKEN_PLACEHOLDER#$SNYK_TOKEN#g; s#AWS_ACCOUNT_ID_PLACEHOLDER#$AWS_ACCOUNT_ID#g" /opt/devsecops/casc.yaml

cd /opt/devsecops
docker compose up -d sonarqube

for i in $(seq 1 90); do
  STATUS=$(curl -s -L http://127.0.0.1:9000/sonarqube/api/system/status | grep -o '"status":"[A-Z]*"' || true)
  if echo "$STATUS" | grep -q "UP" 2>/dev/null; then
    break
  fi
  sleep 10
done

DEFAULT_CHECK=$(curl -s -L -u admin:admin http://127.0.0.1:9000/sonarqube/api/authentication/validate || true)
if echo "$DEFAULT_CHECK" | grep -q '"valid":true' 2>/dev/null; then
  curl -s -L -u admin:admin -X POST "http://127.0.0.1:9000/sonarqube/api/users/change_password" \
    --data-urlencode "login=admin" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=$SONAR_ADMIN_PASSWORD" || true
fi

curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://127.0.0.1:9000/sonarqube/api/user_tokens/revoke" -d "name=jenkins" >/dev/null || true
TOKEN_RESPONSE=$(curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://127.0.0.1:9000/sonarqube/api/user_tokens/generate" -d "name=jenkins" || echo "")
SONAR_TOKEN=$(echo "$TOKEN_RESPONSE" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' || echo "")

if [ -n "$SONAR_TOKEN" ]; then
  sed -i "s#SONAR_TOKEN_PLACEHOLDER#$SONAR_TOKEN#" /opt/devsecops/casc.yaml
  aws secretsmanager put-secret-value --secret-id devsecops-pipeline/sonar-token --region ${aws_region} --secret-string "$SONAR_TOKEN" || true
fi

# Use $EC2_PRIVATE_IP without curly braces so Terraform templatefile() does not interpolate it
curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://127.0.0.1:9000/sonarqube/api/webhooks/create" \
  -d "name=jenkins&url=http://$EC2_PRIVATE_IP:8080/sonarqube-webhook/" >/dev/null || true

JENKINS_BUILD_OK=false
for i in $(seq 1 5); do
  if docker compose up -d --build jenkins; then
    JENKINS_BUILD_OK=true
    break
  fi
  echo "Jenkins docker compose build failed, retrying in 30 seconds... (attempt $i/5)"
  sleep 30
done

if [ "$JENKINS_BUILD_OK" != "true" ]; then
  echo "jenkins image build failed after 5 attempts" > /opt/devsecops/bootstrap-failed
  exit 1
fi

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_repository_url} || true

# Wait until Jenkins finishes loading Configuration-as-Code and is accepting requests
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w "%%{http_code}" http://127.0.0.1:8080/login | grep -q "200"; then
    break
  fi
  sleep 5
done

# Automatically trigger the first pipeline build so Jenkins primes the githubPush webhook
# Written without curly braces so Terraform templatefile() does not attempt variable interpolation
CRUMB=$(curl -s -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" "http://127.0.0.1:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" || true)
if [ -n "$CRUMB" ]; then
  curl -s -X POST -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" -H "$CRUMB" "http://127.0.0.1:8080/job/devsecops-pipeline/build" || true
else
  curl -s -X POST -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" "http://127.0.0.1:8080/job/devsecops-pipeline/build" || true
fi

touch /opt/devsecops/bootstrap-complete
