.PHONY: setup preflight check-vars up down infra k8s lambda test lint docs

VENV_DIR = .venv
VENV_BIN = $(VENV_DIR)/bin
ANSIBLE  = $(VENV_BIN)/ansible-playbook
STAMP    = $(VENV_DIR)/.installed

$(STAMP):
	bash ansible/control-node-setup.sh
	@touch $(STAMP)

setup: $(STAMP)
	@echo "------------------------------------------------------------------------"
	@echo "[SETUP] venv ready, collections installed, kubectl and helm present"
	@echo "[NEXT] export TF_VAR_snyk_token and TF_VAR_budget_alert_email, then run: make infra"
	@echo "------------------------------------------------------------------------"

preflight: $(STAMP)
	cd ansible && ../$(ANSIBLE) playbooks/preflight.yml

check-vars:
	@if [ -z "$$TF_VAR_snyk_token" ]; then \
		echo "[ENV] export TF_VAR_snyk_token=your-snyk-token first"; exit 1; \
	fi
	@if [ -z "$$TF_VAR_budget_alert_email" ]; then \
		echo "[ENV] export TF_VAR_budget_alert_email=your-email first"; exit 1; \
	fi
	@echo "[ENV] required variables present"

up: preflight check-vars
	@echo "[UP] provisioning bootstrap, real infra, k8s security, lambda. jenkins and sonarqube boot themselves on the ec2 instance during infra"
	cd ansible && ../$(ANSIBLE) playbooks/site.yml
	@echo "[UP] complete"

infra: preflight check-vars
	@echo "[INFRA] terraform init and apply against terraform/bootstrap then terraform/environments/aws-cloud, ec2 boots jenkins and sonarqube itself as part of this step"
	cd ansible && ../$(ANSIBLE) playbooks/provision-infra.yml

k8s: preflight
	@echo "[K8S] applying rbac, kyverno policies and falco"
	cd ansible && ../$(ANSIBLE) playbooks/deploy-k8s-security.yml

lambda: preflight
	@echo "[LAMBDA] packaging and deploying the remediation function"
	cd ansible && ../$(ANSIBLE) playbooks/deploy-lambda.yml

test: preflight
	@echo "[TEST] running the falco quarantine end to end test"
	cd ansible && ../$(ANSIBLE) playbooks/test-quarantine.yml

down: preflight
	@echo "[TEARDOWN] destroying every cloud resource this branch created, including the state backend bootstrap, no trace left"
	cd ansible && ../$(ANSIBLE) playbooks/teardown.yml
	rm -rf $(VENV_DIR)
	@echo "[TEARDOWN] complete"

lint: $(STAMP)
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
