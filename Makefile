.PHONY: up down test infra jenkins k8s lambda vault-init vault-encrypt galaxy-install lint docs

VENV_DIR = .venv
VENV_BIN = $(VENV_DIR)/bin
PIP      = $(VENV_BIN)/pip
ANSIBLE  = $(VENV_BIN)/ansible-playbook
VAULT_PASS_FILE = .vault_pass
STAMP = $(VENV_DIR)/.installed

$(VAULT_PASS_FILE):
	@openssl rand -base64 32 > $(VAULT_PASS_FILE)
	@chmod 600 $(VAULT_PASS_FILE)

$(STAMP):
	@python3 -m venv $(VENV_DIR)
	@$(PIP) install --quiet --upgrade pip
	@$(PIP) install --quiet ansible ansible-lint==26.6.0
	@$(PIP) install --quiet boto3 botocore docker flake8 pytest
	@$(PIP) install --quiet -r aws/lambda/requirements-test.txt
	@$(VENV_BIN)/ansible-galaxy collection install -r ansible/requirements.yml
	@touch $(STAMP)

galaxy-install: $(STAMP)

vault-init: galaxy-install $(VAULT_PASS_FILE)
	@test -f ansible/group_vars/all/vault.yml || \
		(cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml && \
		 echo "edit ansible/group_vars/all/vault.yml, set your snyk token, then run: make vault-encrypt")

vault-encrypt: $(VAULT_PASS_FILE)
	$(VENV_BIN)/ansible-vault encrypt ansible/group_vars/all/vault.yml --vault-password-file $(VAULT_PASS_FILE)

up: galaxy-install $(VAULT_PASS_FILE)
	cd ansible && ../$(ANSIBLE) playbooks/site.yml --vault-password-file ../$(VAULT_PASS_FILE)

infra: galaxy-install
	cd ansible && ../$(ANSIBLE) playbooks/provision-infra.yml

jenkins: galaxy-install $(VAULT_PASS_FILE)
	cd ansible && ../$(ANSIBLE) playbooks/bootstrap-jenkins.yml --vault-password-file ../$(VAULT_PASS_FILE)

k8s: galaxy-install
	cd ansible && ../$(ANSIBLE) playbooks/deploy-k8s-security.yml

lambda: galaxy-install
	cd ansible && ../$(ANSIBLE) playbooks/deploy-lambda.yml

test: galaxy-install
	cd ansible && ../$(ANSIBLE) playbooks/test-quarantine.yml

down: galaxy-install
	cd ansible && ../$(ANSIBLE) playbooks/teardown.yml

lint: galaxy-install
	terraform fmt -check -recursive terraform/
	cd terraform/environments/aws && terraform init -backend=false && terraform validate
	tflint --chdir=terraform/environments/aws --init
	tflint --chdir=terraform/environments/aws
	checkov -d terraform/ --quiet
	$(VENV_BIN)/ansible-lint ansible/playbooks/*.yml

docs:
	terraform-docs markdown table terraform/modules/vpc > terraform/modules/vpc/README.md
	terraform-docs markdown table terraform/modules/eks > terraform/modules/eks/README.md
	terraform-docs markdown table terraform/modules/ecr > terraform/modules/ecr/README.md
	terraform-docs markdown table terraform/modules/iam > terraform/modules/iam/README.md
	terraform-docs markdown table terraform/modules/sns > terraform/modules/sns/README.md
