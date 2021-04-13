
provider "aws" {
  region  = var.region
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name                 = "${var.cluster_name}-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  # We can use private subnets too once https://github.com/aws/containers-roadmap/issues/607
  # is fixed
  public_subnets       = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Owner = split("/", data.aws_caller_identity.current.arn)[1]
    AutoTag_Creator = data.aws_caller_identity.current.arn
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name = var.cluster_name
  cluster_version = "1.18"
  # FIXME: We can use private subnets once https://github.com/aws/containers-roadmap/issues/607
  # is fixed
  subnets      = module.vpc.public_subnets
  vpc_id       = module.vpc.vpc_id
  enable_irsa  = true

  tags = {
    Owner = split("/", data.aws_caller_identity.current.arn)[1]
    AutoTag_Creator = data.aws_caller_identity.current.arn
  }

  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 50
  }

  node_groups = {
    core = {
      desired_capacity = 1
      max_capacity     = 3
      min_capacity     = 1
      instance_type = "t3.micro"
      k8s_labels    = {
        "hub.jupyter.org/node-purpose" =  "core"
      }
      additional_tags = {
      }
    }
    notebook = {
     desired_capacity = 1
     max_capacity     = 10
     min_capacity     = 1

     instance_type = "t3.medium"
     k8s_labels = {
       "hub.jupyter.org/node-purpose" =  "user"
     }
     additional_tags = {
     }
    }
  }

  map_accounts = var.map_accounts
  map_users = var.map_users


  map_roles = concat([{
    rolearn  = aws_iam_role.hubploy_eks.arn
    username = aws_iam_role.hubploy_eks.name
    # FIXME: Narrow these permissions down?
    groups   = ["system:masters"]
  }], var.map_roles)
}


provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
