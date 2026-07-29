#!/bin/bash
exec > >(tee -a /var/log/user-data.log | tee /dev/console) 2>&1
set -euo pipefail
set -x

dnf install -y docker amazon-efs-utils awscli git
systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" >> /etc/sysctl.conf

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

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

JENKINS_ADMIN_USER=$(aws secretsmanager get-secret-value --secret-id devsecops-pipeline/jenkins-admin-user --region ${aws_region} --query SecretString --output text)
JENKINS_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id devsecops-pipeline/jenkins-admin-password --region ${aws_region} --query SecretString --output text)
SONAR_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id devsecops-pipeline/sonar-admin-password --region ${aws_region} --query SecretString --output text)
SNYK_TOKEN=$(aws secretsmanager get-secret-value --secret-id devsecops-pipeline/snyk-token --region ${aws_region} --query SecretString --output text)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > /opt/devsecops/docker-compose.yml << 'COMPOSEEOF'
services:
  jenkins:
    build:
      context: /opt/devsecops/repo
      dockerfile: Dockerfile.jenkins
    image: jenkins-devsecops:lts-jdk21
    container_name: jenkins
    user: root
    mem_limit: 3g
    cpus: 2.0
    ports:
      - "8080:8080"
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
    url: http://jenkins:8080/
  sonarGlobalConfiguration:
    buildWrapperEnabled: true
    installations:
      - name: SonarQube
        serverUrl: http://sonarqube:9000/sonarqube
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

for i in $(seq 1 60); do
  STATUS=$(curl -s -L http://localhost:9000/sonarqube/api/system/status | grep -o '"status":"[A-Z]*"' || echo "")
  if echo "$STATUS" | grep -q "UP"; then
    break
  fi
  sleep 10
done

DEFAULT_CHECK=$(curl -s -L -u admin:admin http://localhost:9000/sonarqube/api/authentication/validate || echo "")
if echo "$DEFAULT_CHECK" | grep -q '"valid":true'; then
  curl -s -L -u admin:admin -X POST "http://localhost:9000/sonarqube/api/users/change_password" \
    --data-urlencode "login=admin" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=$SONAR_ADMIN_PASSWORD"
fi

curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/sonarqube/api/user_tokens/revoke" -d "name=jenkins" >/dev/null || true
TOKEN_RESPONSE=$(curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/sonarqube/api/user_tokens/generate" -d "name=jenkins")
SONAR_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])" || echo "TOKEN_GEN_FAILED")

if [ "$SONAR_TOKEN" != "TOKEN_GEN_FAILED" ] && [ -n "$SONAR_TOKEN" ]; then
  sed -i "s#SONAR_TOKEN_PLACEHOLDER#$SONAR_TOKEN#" /opt/devsecops/casc.yaml
  aws secretsmanager put-secret-value --secret-id devsecops-pipeline/sonar-token --region ${aws_region} --secret-string "$SONAR_TOKEN"
fi

curl -s -L -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "http://localhost:9000/sonarqube/api/webhooks/create" \
  -d "name=jenkins&url=http://jenkins:8080/sonarqube-webhook/" >/dev/null || true

docker compose up -d --build jenkins

aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin ${ecr_repository_url}

touch /opt/devsecops/bootstrap-complete
