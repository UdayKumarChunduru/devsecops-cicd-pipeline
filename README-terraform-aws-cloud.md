# terraform-aws-cloud branch

Everything from terraform-aws, but nothing runs on your laptop. Jenkins
and SonarQube run on EC2, image builds run in CodeBuild, secrets live
in Secrets Manager, and every terraform apply and ansible playbook run
happens inside GitHub Actions using OIDC federation, no stored AWS
keys anywhere. See SECURITY.md for the full security model.

## One time setup

    export TF_VAR_snyk_token=your_snyk_token
    export TF_VAR_budget_alert_email=your_email
    make setup

Creates a local .venv, installs ansible and every collection this
branch needs, checks for kubectl and helm. Nothing installs into
system python.

## Deploy everything

    make infra
    make k8s
    make lambda
    make test

Or all four in one shot:

    make up

infra runs terraform init and apply against terraform/bootstrap first
(state bucket, dynamodb lock, github actions oidc trust), then against
terraform/environments/aws-cloud (vpc, eks, ecr, sns, iam, efs,
secrets, codebuild, compute, budget). Jenkins and sonarqube boot
themselves automatically on the ec2 instance as part of this step,
there is no separate make jenkins target, that job moved entirely
into the ec2 user-data script.

After infra finishes, note the github actions role arn printed in the
output, add it to the repo as secret AWS_GITHUB_ACTIONS_ROLE_ARN if
you want future pushes to trigger deploys through github actions
instead of running make up locally every time. This is optional,
make up works fully on its own without it.

## Teardown

    make down

Destroys every resource this branch created, including the state
backend bootstrap, nothing survives in the aws account. If you had
set the AWS_GITHUB_ACTIONS_ROLE_ARN github secret, it goes stale after
this, the next make infra recreates the role with the same name but a
new arn, update the secret before relying on github actions to deploy
again.

## Accessing Jenkins and SonarQube

Neither is reachable from the public internet. Both go through an IAM
authenticated SSM tunnel:

    INSTANCE_ID=$(cd terraform/environments/aws-cloud && terraform output -raw instance_id)

    aws ssm start-session \
      --target $INSTANCE_ID \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'

Open http://localhost:8080. Same pattern with portNumber 9000 in a
separate terminal for http://localhost:9000/sonarqube.

Get admin credentials:

    aws secretsmanager get-secret-value --secret-id devsecops-pipeline/jenkins-admin-password --query SecretString --output text
    aws secretsmanager get-secret-value --secret-id devsecops-pipeline/sonar-admin-password --query SecretString --output text

## Every future change

    git add ...
    git commit -s -m "..." -m "..."
    git push origin terraform-aws-cloud

GitHub Actions applies the change automatically.

## Teardown

GitHub repo -> Actions tab -> teardown terraform-aws-cloud -> Run
workflow -> type destroy in the confirm field -> Run workflow. Does
not touch terraform/bootstrap, that persists intentionally.

## Local linting before you push

    make lint
