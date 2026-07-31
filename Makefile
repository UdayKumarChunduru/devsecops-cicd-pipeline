.PHONY: setup preflight check-vars up down infra bootstrap aws-cloud k8s lambda test lint docs galaxy-install

VENV_DIR = .venv
VENV_BIN = $(VENV_DIR)/bin
ANSIBLE  = $(VENV_BIN)/ansible-playbook
STAMP    = $(VENV_DIR)/.installed
ANSIBLE_ARGS ?= -vvvv

ANSIBLE_RUN = cd ansible && ../$(ANSIBLE) $(ANSIBLE_ARGS)

$(STAMP):
	@if [ -d "$(VENV_DIR)" ]; then \
		echo "[VENV] existing virtualenv found at $(VENV_DIR), reusing it"; \
	else \
		echo "[VENV] no virtualenv found, creating one at $(VENV_DIR)"; \
		python3 -m venv $(VENV_DIR); \
		echo "[VENV] virtualenv created at $(VENV_DIR)"; \
	fi
	@$(VENV_BIN)/pip install --upgrade pip --quiet
	@$(VENV_BIN)/pip install --quiet ansible boto3 botocore kubernetes flake8 pytest ansible-lint
	@echo "[GALAXY] checking ansible collections against ansible/requirements.yml"
	@$(VENV_BIN)/ansible-galaxy collection install -r ansible/requirements.yml
	@touch $(STAMP)
	@echo "[VENV] setup complete"

galaxy-install: $(STAMP)

preflight: galaxy-install
	@echo "[PREFLIGHT] verifying terraform, ansible, aws, kubectl, eksctl, helm, python3, docker and aws credentials"
	@$(ANSIBLE_RUN) playbooks/preflight.yml
	@echo "[PREFLIGHT] all required tools present, aws identity confirmed"

check-vars:
	@if [ -z "$$TF_VAR_snyk_token" ]; then \
		echo "[ENV] export TF_VAR_snyk_token=your-snyk-token first"; exit 1; \
	fi
	@if [ -z "$$TF_VAR_budget_alert_email" ]; then \
		echo "[ENV] export TF_VAR_budget_alert_email=your-email first"; exit 1; \
	fi
	@echo "[ENV] required variables present"

setup: galaxy-install preflight check-vars
	@echo "------------------------------------------------------------------------"
	@echo "[SETUP] control node ready, tools verified, and variables checked"
	@echo "[NEXT] run: make up"
	@echo "------------------------------------------------------------------------"

up: galaxy-install preflight check-vars infra k8s lambda test
	@echo "[UP] complete pipeline executed successfully"

bootstrap: check-vars
	@echo "[BOOTSTRAP] applying terraform state backend bootstrap only"
	@$(ANSIBLE_RUN) playbooks/provision-bootstrap.yml

aws-cloud: check-vars
	@echo "[AWS-CLOUD] applying terraform real environment and spawning SSM tunnels"
	@$(ANSIBLE_RUN) playbooks/provision-cloud.yml

infra: check-vars bootstrap aws-cloud
	@echo "[INFRA] complete infrastructure provisioning finished successfully"

k8s:
	@echo "[K8S] applying rbac, kyverno policies and falco"
	@$(ANSIBLE_RUN) playbooks/deploy-k8s-security.yml

lambda:
	@echo "[LAMBDA] packaging and deploying the remediation function"
	@$(ANSIBLE_RUN) playbooks/deploy-lambda.yml

test:
	@echo "[TEST] running the falco quarantine end to end test"
	@$(ANSIBLE_RUN) playbooks/test-quarantine.yml

down:
	@echo "[TEARDOWN] destroying every cloud resource this branch created"
	@$(ANSIBLE_RUN) playbooks/teardown.yml
	@echo "[TEARDOWN] removing local python virtual environment"
	@rm -rf $(VENV_DIR)
	@echo "[TEARDOWN] complete"

lint: galaxy-install
	terraform fmt -check -recursive terraform/
	cd terraform/environments/aws-cloud && terraform init -backend=false && terraform validate
	tflint --chdir=terraform/environments/aws-cloud --init
	tflint --chdir=terraform/environments/aws-cloud
	checkov -d terraform/ --quiet --config-file .checkov.yaml
	$(VENV_BIN)/ansible-lint ansible/playbooks/*.yml

docs:
	terraform-docs markdown table terraform/modules/vpc > terraform/modules/vpc/README.md
	terraform-docs markdown table terraform/modules/eks > terraform/modules/eks/README.md
	terraform-docs markdown table terraform/modules/ecr > terraform/modules/ecr/README.md
	terraform-docs markdown table terraform/modules/iam > terraform/modules/iam/README.md
	terraform-docs markdown table terraform/modules/sns > terraform/modules/sns/README.md
	terraform-docs markdown table terraform/modules/efs > terraform/modules/efs/README.md
	terraform-docs markdown table terraform/modules/secrets > terraform/modules/secrets/README.md
	terraform-docs markdown table terraform/modules/codebuild > terraform/modules/codebuild/README.md
	terraform-docs markdown table terraform/modules/compute > terraform/modules/compute/README.md
	terraform-docs markdown table terraform/modules/budget > terraform/modules/budget/README.md
