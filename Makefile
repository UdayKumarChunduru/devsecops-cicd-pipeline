.PHONY: up down test infra jenkins k8s lambda vault-init galaxy-install lint docs

galaxy-install:
	ansible-galaxy collection install -r ansible/requirements.yml
	pip install boto3 botocore docker --break-system-packages
	pip install -r aws/lambda/requirements-test.txt --break-system-packages
	pip install flake8 --break-system-packages

vault-init:
	@test -f ansible/group_vars/all/vault.yml || \
		(cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml && \
		 echo "edit ansible/group_vars/all/vault.yml with real values, then run: ansible-vault encrypt ansible/group_vars/all/vault.yml")

up: galaxy-install
	cd ansible && ansible-playbook playbooks/site.yml --ask-vault-pass

infra:
	cd ansible && ansible-playbook playbooks/provision-infra.yml

jenkins:
	cd ansible && ansible-playbook playbooks/bootstrap-jenkins.yml --ask-vault-pass

k8s:
	cd ansible && ansible-playbook playbooks/deploy-k8s-security.yml

lambda:
	cd ansible && ansible-playbook playbooks/deploy-lambda.yml

test:
	cd ansible && ansible-playbook playbooks/test-quarantine.yml

down:
	cd ansible && ansible-playbook playbooks/teardown.yml

lint:
	terraform fmt -check -recursive terraform/
	cd terraform/environments/aws && terraform init -backend=false && terraform validate
	tflint --chdir=terraform/environments/aws --init
	tflint --chdir=terraform/environments/aws
	checkov -d terraform/ --quiet
	ansible-lint ansible/playbooks/*.yml

docs:
	terraform-docs markdown table terraform/modules/vpc > terraform/modules/vpc/README.md
	terraform-docs markdown table terraform/modules/eks > terraform/modules/eks/README.md
	terraform-docs markdown table terraform/modules/ecr > terraform/modules/ecr/README.md
	terraform-docs markdown table terraform/modules/iam > terraform/modules/iam/README.md
	terraform-docs markdown table terraform/modules/sns > terraform/modules/sns/README.md
