.PHONY: vault-setup up down test infra jenkins k8s lambda vault-init vault-encrypt vault-reset galaxy-install preflight lint docs

VENV_DIR = .venv
VENV_BIN = $(VENV_DIR)/bin
ANSIBLE  = $(VENV_BIN)/ansible-playbook
VAULT_PASS_FILE = .vault_pass
STAMP = $(VENV_DIR)/.installed
ANSIBLE_ARGS ?= -v

$(VAULT_PASS_FILE):
	@echo "[VAULT] no vault password file found at $(VAULT_PASS_FILE), generating one"
	@openssl rand -base64 32 > $(VAULT_PASS_FILE)
	@chmod 600 $(VAULT_PASS_FILE)
	@echo "[VAULT] vault password file created at $(VAULT_PASS_FILE)"

$(STAMP):
	@if [ -d "$(VENV_DIR)" ]; then \
		echo "[VENV] existing virtualenv found at $(VENV_DIR), reusing it"; \
	else \
		echo "[VENV] no virtualenv found, creating one at $(VENV_DIR)"; \
		python3 -m venv $(VENV_DIR); \
		echo "[VENV] virtualenv created at $(VENV_DIR)"; \
	fi
	@bash scripts/venv-install.sh $(VENV_BIN) ansible ansible-lint==26.6.0 boto3 botocore docker flake8 pytest -r aws/lambda/requirements-test.txt
	@echo "[GALAXY] checking ansible collections against ansible/requirements.yml"
	@$(VENV_BIN)/ansible-galaxy collection install -r ansible/requirements.yml
	@touch $(STAMP)
	@echo "[VENV] setup complete"

galaxy-install: $(STAMP)

preflight: galaxy-install
	@echo "[PREFLIGHT] verifying terraform, aws, kubectl, helm, zip, python3, docker and aws credentials"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/preflight.yml
	@echo "[PREFLIGHT] all required tools present, aws identity confirmed"

vault-init: galaxy-install $(VAULT_PASS_FILE)
	@if [ -f ansible/group_vars/all/vault.yml ]; then \
		echo "[VAULT] ansible/group_vars/all/vault.yml already exists, leaving it untouched"; \
	else \
		cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml; \
		echo "[VAULT] created ansible/group_vars/all/vault.yml from the example template"; \
		echo "[VAULT] edit it now with your real snyk token, then run: make vault-encrypt"; \
	fi

vault-encrypt: $(VAULT_PASS_FILE)
	@if [ ! -f ansible/group_vars/all/vault.yml ]; then \
		echo "[VAULT] ansible/group_vars/all/vault.yml does not exist"; \
		echo "[VAULT] run: make vault-setup"; \
		exit 1; \
	fi
	@if grep -q '^\$$ANSIBLE_VAULT' ansible/group_vars/all/vault.yml 2>/dev/null; then \
		echo "[VAULT] vault.yml is already encrypted, nothing to do"; \
	else \
		$(VENV_BIN)/ansible-vault encrypt ansible/group_vars/all/vault.yml --vault-password-file $(VAULT_PASS_FILE) || \
			(echo "[VAULT] encryption failed, see error above" && exit 1); \
		echo "[VAULT] vault.yml encrypted successfully with $(VAULT_PASS_FILE)"; \
	fi

vault-reset:
	@echo "[VAULT] recreating vault.yml from the example template, any values in the current encrypted file are lost unless saved elsewhere"
	@rm -f ansible/group_vars/all/vault.yml
	@cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
	@echo "[VAULT] vault.yml reset, edit it and run make vault-encrypt again"

vault-setup: preflight vault-init
	@echo "------------------------------------------------------------------------"
	@echo "[VAULT] Initialization complete."
	@echo "[STEP 1] Open 'ansible/group_vars/all/vault.yml' and paste your Snyk Token."
	@echo "[STEP 2] Save the file, then run this command to deploy your stack:"
	@echo "         make up"
	@echo "------------------------------------------------------------------------"

up: preflight $(VAULT_PASS_FILE) vault-encrypt
	@echo "[PROVISION] Vault secured. Provisioning full stack (Infra, K8s, Lambda, Jenkins)..."
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/site.yml --vault-password-file ../$(VAULT_PASS_FILE)
	@echo "[PROVISION] Complete! Run 'cat .pipeline-credentials' for access logins."

infra: preflight
	@echo "[INFRA] applying terraform state backend then the real environment"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/provision-infra.yml

jenkins: preflight $(VAULT_PASS_FILE)
	@echo "[JENKINS] bootstrapping sonarqube and jenkins with configuration as code"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/bootstrap-jenkins.yml --vault-password-file ../$(VAULT_PASS_FILE)

k8s: preflight
	@echo "[K8S] applying rbac, kyverno policies and falco"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/deploy-k8s-security.yml

lambda: preflight
	@echo "[LAMBDA] packaging and deploying the remediation function"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/deploy-lambda.yml

test: preflight
	@echo "[TEST] running the falco quarantine end to end test"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/test-quarantine.yml

down:
	@echo "[TEARDOWN] destroying every cloud and local resource this branch created"
	cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS) playbooks/teardown.yml
	@echo "[VENV] Teardown successful! Safely removing local python virtual environment..."
	rm -rf $(VENV_DIR)
	@echo "[TEARDOWN] complete, verify with aws eks list-clusters, aws ecr describe-repositories, aws lambda list-functions"

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
