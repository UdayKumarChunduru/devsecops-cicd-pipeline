# aws environment

Requires terraform/bootstrap to have been applied first, its two outputs
must match the values in backend.tf here.

## Run

    cd terraform/environments/aws
    terraform init
    terraform plan
    terraform apply

Takes 12-18 minutes.

## Destroy

    terraform destroy

Ansible's teardown playbook calls this for you as its final step.
