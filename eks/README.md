# EKS cluster lifecycle for the aws branch

## Create
    eksctl create cluster -f eks/cluster.yaml
    # takes 15-20 minutes, eksctl handles VPC, subnets, NAT gateway, IAM
    # roles for the node group, and the OIDC provider automatically

## Tear down when done testing
    eksctl delete cluster -f eks/cluster.yaml
    # this is the expected end-of-session step for this branch, not an
    # afterthought - there is no reason to leave this running idle
