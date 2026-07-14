# State backend bootstrap

Run once, before anything else in terraform/environments. Uses local state
since a bucket that will hold remote state cannot itself be created using
that same remote state.

S3 bucket names are globally unique across all AWS accounts. If
devsecops-pipeline-tfstate is already taken, override it:

    terraform apply -var="state_bucket_name=devsecops-pipeline-tfstate-<account-id>"

## Run

    cd terraform/bootstrap
    terraform init
    terraform apply

Note the two output values, they go into every backend.tf in
terraform/environments/*.
