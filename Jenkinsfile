pipeline {
    agent any

    environment {
        APP_NAME       = 'demo-service'
        NEXUS_REGISTRY = 'nexus:8082'
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

        stage('Static analysis - SonarQube') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        dir('app') {
                            sh 'mvn clean verify sonar:sonar -B -Dsonar.host.url=$SONAR_HOST_URL -Dsonar.token=$SONAR_TOKEN -Dsonar.projectBaseDir=. ${MAVEN_OPTS}'
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
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            sh '''
                              snyk auth $SNYK_TOKEN
                              snyk test --severity-threshold=high --maven-repo-path=/var/jenkins_home/.m2/repository
                            '''
                        }
                    }
                }
            }
        }

        stage('Dependency scan - Trivy FS') {
            steps {
                dir('app') {
                    sh 'trivy fs --severity HIGH,CRITICAL .'
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
                  docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    aquasec/trivy:latest \
                    image --exit-code 1 --severity CRITICAL --no-progress $IMAGE

                  docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    aquasec/trivy:latest \
                    image --severity HIGH,MEDIUM --no-progress $IMAGE || true
                '''
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
