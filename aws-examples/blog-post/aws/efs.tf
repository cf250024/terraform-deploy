resource "aws_efs_file_system" "home_dirs" {
  tags = {
    Name = "${var.cluster_name}-home-dirs"
  }
}


resource "aws_security_group" "home_dirs_sg" {
  name   = "home_dirs_sg"
  vpc_id = module.vpc.vpc_id

  # NFS
  ingress {

    # FIXME: Is ther a way to do this without CIDR block copy/pasta
    cidr_blocks = [ "172.16.0.0/16"]
    # FIXME: Do we need this security_groups here along with cidr_blocks
    security_groups = [ module.eks.worker_security_group_id ]
    from_port        = 2049
    to_port          = 2049
    protocol         = "tcp"
  }

  tags = {
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
}

resource "aws_iam_policy" "aws_efs_csi_driver" {
  name   = "efs-csi-policy"
  policy = <<-EOD
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:CreateAccessPoint"
        ],
        "Resource": "*",
        "Condition": {
          "StringLike": {
            "aws:RequestTag/efs.csi.aws.com/cluster": "true",
            "aws:RequestTag/cluster-name": "${var.cluster_name}"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": "elasticfilesystem:DeleteAccessPoint",
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:ResourceTag/efs.csi.aws.com/cluster": "true",
            "aws:ResourceTag/cluster-name": "${var.cluster_name}"
          }
        }
      }
    ]
  }
  EOD
}

resource "aws_iam_role" "efs_csi_role" {
  name = "efs-csi-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::653480936020:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/0397DABF2ABB69344C70010FD2582753"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-west-2.amazonaws.com/id/0397DABF2ABB69344C70010FD2582753:sub": "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }
  ]}
EOF
}

resource "aws_iam_role_policy_attachment" "efs-csi-attach" {
  role       = "${aws_iam_role.efs_csi_role.name}"
  policy_arn = "${aws_iam_policy.aws_efs_csi_driver.arn}"
}