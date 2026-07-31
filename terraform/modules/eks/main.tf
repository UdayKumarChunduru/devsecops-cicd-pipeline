terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=d4669ca8eb109a37f6c19ab8fb9487ab7521a9ba"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id                  = var.vpc_id
  subnet_ids              = var.private_subnet_ids
  endpoint_public_access  = true
  endpoint_private_access = true
  authentication_mode     = "API_AND_CONFIG_MAP"

  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    devsecops-workers = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      disk_size = var.node_volume_size

      labels = {
        role = "worker"
      }
    }
  }

  tags = {
    project = "devsecops-pipeline"
  }
}

resource "aws_security_group_rule" "cluster_vpc_https" {
  description       = "Allow VPC inbound HTTPS to EKS control plane API"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = module.eks.cluster_security_group_id
}
