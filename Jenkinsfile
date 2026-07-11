pipeline {
    agent any

    environment {
        APP_NAME       = 'demo-service'
        NEXUS_REGISTRY = 'localhost:8082'
        SONAR_HOST_URL = 'http://sonarqube:9000'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        IMAGE          = "${NEXUS_REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
        MAVEN_OPTS     = "-Xmx1024m -Dmaven.repo.local=/var/jenkins_home/.m2/repository"
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
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
                      pip install --break-system-packages --quiet flake8 -r requirements-test.txt
                      flake8 falco_remediation.py tests/ --max-line-length=100 --ignore=E501,W503
                      python3 -m pytest tests/ -v
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

        stage('Build image') {
            steps {
                dir('app') {
                    sh 'docker build -t $IMAGE .'
                }
            }
        }

        stage('Image scan - Trivy') {
            steps {
                sh '''
                  trivy image --timeout 15m --exit-code 1 --severity CRITICAL --ignorefile .trivyignore --no-progress $IMAGE
                  trivy image --timeout 15m --severity HIGH,MEDIUM --ignorefile .trivyignore --no-progress $IMAGE || true
                '''
            }
        }

        stage('Generate SBOM - Trivy') {
            steps {
                sh 'trivy image --format cyclonedx --output sbom-$IMAGE_TAG.json $IMAGE'
            }
            post {
                always { archiveArtifacts artifacts: 'sbom-*.json', allowEmptyArchive: true }
            }
        }

        stage('Push to Nexus') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                    sh '''
                      echo "$NEXUS_PASS" | docker login $NEXUS_REGISTRY -u "$NEXUS_USER" --password-stdin
                      docker push $IMAGE
                      docker logout $NEXUS_REGISTRY
                    '''
                }
            }
        }

        stage('Load image into kind') {
            steps {
                sh 'kind load docker-image $IMAGE --name devsecops'
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                      sed "s|IMAGE_PLACEHOLDER|$IMAGE|" k8s/deployment.yaml | kubectl apply -f -
                      kubectl apply -f k8s/service.yaml
                      kubectl rollout status deployment/demo-service --timeout=120s
                    '''
                }
            }
        }
    }

    post {
        failure {
            echo "Build ${env.BUILD_NUMBER} failed. Check the stage logs and archived scanner reports."
        }
    }
}
