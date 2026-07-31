pipeline {
    agent any

    environment {
        APP_NAME          = 'demo-service'
        AWS_REGION        = 'us-east-1'
        AWS_ACCOUNT_ID    = credentials('aws-account-id')
        SONAR_HOST_URL    = 'http://127.0.0.1:9000/sonarqube'
        MAVEN_OPTS        = "-Xmx1024m -Dmaven.repo.local=/var/jenkins_home/.m2/repository"
        EKS_CLUSTER_NAME  = 'devsecops-real'
        K8S_NAMESPACE     = 'devsecops-pipeline'
        CODEBUILD_PROJECT = 'devsecops-image-build'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Secret scan - Gitleaks') {
            steps {
                sh '''
                  gitleaks detect \
                  --no-git \
                  --source . \
                  --report-format json \
                  --report-path gitleaks-report.json
                '''
            }
            post {
                always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true }
            }
        }

        stage('Lambda - lint and test') {
            steps {
                dir('aws/lambda') {
                    sh '''
                      if [ ! -d ".venv" ]; then
                          python3 -m venv .venv
                      fi

                      VENV_BIN=".venv/bin"

                      $VENV_BIN/pip install --upgrade pip --quiet
                      $VENV_BIN/pip install --quiet flake8 -r requirements-test.txt

                      $VENV_BIN/flake8 falco_remediation.py tests/ --max-line-length=100 --ignore=E501,W503
                      $VENV_BIN/python3 -m pytest tests/ -v
                    '''
                }
            }
        }

        stage('Static analysis - SonarQube') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        dir('app') {
                            sh 'mvn clean verify org.sonarsource.scanner.maven:sonar-maven-plugin:4.0.0.4121:sonar -B -Dsonar.host.url=$SONAR_HOST_URL -Dsonar.token=$SONAR_TOKEN -Dsonar.projectBaseDir=.'
                        }
                    }
                }
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Dependency scan - Snyk') {
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    dir('app') {
                        sh '''
                          snyk auth $SNYK_TOKEN
                          snyk test --severity-threshold=high --maven-repo-path=/var/jenkins_home/.m2/repository
                        '''
                    }
                }
            }
        }

        stage('Build, scan and push image via CodeBuild') {
            steps {
                sh '''
                  BUILD_ID=$(aws codebuild start-build \
                    --project-name $CODEBUILD_PROJECT \
                    --region $AWS_REGION \
                    --source-version $GIT_COMMIT \
                    --query 'build.id' --output text)

                  echo "codebuild build id: $BUILD_ID"

                  while true; do
                    STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --region $AWS_REGION --query 'builds[0].buildStatus' --output text)
                    echo "codebuild status: $STATUS"
                    if [ "$STATUS" = "SUCCEEDED" ]; then
                      break
                    elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "FAULT" ] || [ "$STATUS" = "STOPPED" ] || [ "$STATUS" = "TIMED_OUT" ]; then
                      echo "codebuild did not succeed, status was $STATUS"
                      exit 1
                    fi
                    sleep 15
                  done
                '''
            }
            post {
                aborted {
                    sh '''
                      if [ -n "${BUILD_ID:-}" ]; then
                        aws codebuild stop-build --id "$BUILD_ID" --region $AWS_REGION || true
                      fi
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                  IMAGE_TAG=$(echo $GIT_COMMIT | cut -c1-8)
                  IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}:${IMAGE_TAG}"
                  aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
                  sed "s|IMAGE_PLACEHOLDER|$IMAGE|" k8s/deployment-eks.yaml | kubectl apply -n $K8S_NAMESPACE -f -
                  kubectl apply -n $K8S_NAMESPACE -f k8s/service.yaml
                  kubectl rollout status deployment/demo-service -n $K8S_NAMESPACE --timeout=180s
                '''
            }
        }
    }

    post {
        failure {
            echo "Build ${env.BUILD_NUMBER} failed. Check the stage logs and archived scanner reports."
        }
    }
}
