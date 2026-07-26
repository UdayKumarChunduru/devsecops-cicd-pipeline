# terraform-aws-cloud branch

Everything from terraform-aws, but nothing runs on your laptop. Jenkins
and SonarQube run on EC2, image builds run in CodeBuild, secrets live
in Secrets Manager, and every terraform apply and ansible playbook run
happens inside GitHub Actions using OIDC federation, no stored AWS
keys anywhere. See SECURITY.md for the full security model.

## One time setup

### 1. Bootstrap the OIDC trust relationship

This is the one step that cannot be automated, a human with real AWS
credentials has to create the initial trust between GitHub Actions and
this AWS account, exactly once, ever, for the lifetime of this repo.

    cd terraform/bootstrap
    terraform init
    terraform apply
    terraform output github_actions_role_arn

Copy that ARN. Because it now lives in terraform/bootstrap, not in the
real infrastructure environment, this value never changes again, even
across every future destroy and recreate of the actual EKS/EC2/EFS
stack.

### 2. Add repository secrets

Repo Settings -> Secrets and variables -> Actions -> New repository
secret, add:

    AWS_GITHUB_ACTIONS_ROLE_ARN   the arn from step 1
    SNYK_TOKEN                    from app.snyk.io -> account settings -> auth token
    BUDGET_ALERT_EMAIL            an email you actually check

No IP address secret exists. Jenkins and SonarQube are never reachable
over the public internet at all.

### 3. Push to trigger the first deploy

    git push origin terraform-aws-cloud

The deploy-cloud.yml workflow applies terraform, then runs the
kubernetes security and lambda ansible playbooks. Takes 15-20 minutes,
mostly EKS.

### 4. Add the GitHub webhook

    cd terraform/environments/aws-cloud
    terraform output alb_dns_name

Repo Settings -> Webhooks -> Add webhook, payload URL
`http://<alb-dns-name>/github-webhook/`, content type
`application/json`. One time manual step, the ALB's DNS name only
exists after the first apply.

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
