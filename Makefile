.PHONY: lint docs local-validate

lint:
	terraform fmt -check -recursive terraform/
	cd terraform/environments/aws-cloud && terraform init -backend=false && terraform validate
	tflint --chdir=terraform/environments/aws-cloud --init
	tflint --chdir=terraform/environments/aws-cloud
	checkov -d terraform/ --quiet
	ansible-lint ansible/playbooks/*.yml

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

local-validate:
	cd terraform/environments/aws-cloud && terraform init -backend=false && terraform validate
