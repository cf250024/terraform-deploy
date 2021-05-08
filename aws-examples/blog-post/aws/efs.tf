# Create IAM role + automatically make it available to efs csi driver service account
module "iam_assumable_role_admin_efs" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  create_role                   = true
  role_name                     = "efs-csi-driver-${var.cluster_name}"
  provider_url                  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.aws_efs_csi_driver.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]

  tags = {
    Owner = split("/", data.aws_caller_identity.current.arn)[1]
    AutoTag_Creator = data.aws_caller_identity.current.arn
  }
}

resource "aws_iam_policy" "aws_efs_csi_driver" {
  name_prefix = "cluster-efs"
  description = "EKS efs-csi-driver policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.aws_efs_csi_driver.json
}

data "aws_iam_policy_document" "aws_efs_csi_driver" {
  statement {
    effect    = "Allow"
    actions   = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
    ]
    resources = ["*"]
  }

  statement {
    effect     = "Allow"
    actions    = [
      "elasticfilesystem:CreateAccessPoint",
    ]
    resources  = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    effect     = "Allow"
    actions    = [
      "elasticfilesystem:DeleteAccessPoint",
    ]
    resources  = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
}

resource "aws_efs_file_system" "home_dirs" {
  tags = {
    Name = "${var.cluster_name}-home-dirs"
  }
}

resource "aws_security_group" "home_dirs_sg" {
  name   = "${var.cluster_name}-home-dirs-sg"
  vpc_id = module.vpc.vpc_id

  # NFS
  ingress {

    cidr_blocks = [ var.cidr ]
    from_port        = 2049
    to_port          = 2049
    protocol         = "tcp"
  }

  tags = {
    Name = "${var.cluster_name}-home-dirs-sg"
    Owner = split("/", data.aws_caller_identity.current.arn)[1]
    AutoTag_Creator = data.aws_caller_identity.current.arn
  }
}

resource "aws_efs_mount_target" "home_dirs_targets" {
  count = length(module.vpc.private_subnets)
  file_system_id = aws_efs_file_system.home_dirs.id
  subnet_id = module.vpc.private_subnets[count.index]
  security_groups = [ aws_security_group.home_dirs_sg.id ]
}

resource "helm_release" "efs-provisioner" {
  name = "efs-provisioner"
  namespace = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart = "aws-efs-csi-driver"
  version = "1.2.2"

  values = [
    file("efsvalues.yaml")
  ]

  set {
    name = "storageClasses[0].parameters.fileSystemId"
    value = aws_efs_file_system.home_dirs.id
  }

  set{
    name  = "serviceAccount.controller.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_admin_efs.iam_role_arn
  }

   set{
    name  = "controller.tags"
    value = var.region
  }

}
