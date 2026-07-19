# terraform-aws branch

Same architecture proven on the aws branch, EKS, ECR, SNS,
Lambda, IAM/IRSA, but every piece of infrastructure is declared
in Terraform and every piece of orchestration runs through Ansible
playbooks. No bash scripts, no manual CLI steps.

## One time setup

    make galaxy-install

Creates a local `.venv`, installs ansible, ansible-lint, the aws
python dependencies, and every ansible collection this branch needs.
Nothing installs anything system wide.

    cd terraform/bootstrap
    terraform init
    terraform plan
    terraform apply
    cd ../..

    make vault-init
    ansible-vault encrypt ansible/group_vars/all/vault.yml

## Run everything

    make up

## Individual stages

    make infra
    make jenkins
    make k8s
    make lambda
    make test

## Teardown

    make down

## Linting locally

    make lint
