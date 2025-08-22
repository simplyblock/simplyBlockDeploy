resource "aws_security_group" "eks_nodes_sg" {
  count       = var.enable_eks
  name        = "${terraform.workspace}-eks-sg"
  description = "EKS Worker nodes Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "eks cluster"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }

  ingress {
    from_port       = 8080
    to_port         = 8890
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "For SPDK Proxy for the storage node from mgmt node"
  }

  ingress {
    from_port   = 8080
    to_port     = 8890
    protocol    = "tcp"
    self        = true
    description = "For SPDK Proxy for the storage node from other storage nodes"
  }

  ingress {
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "allow ICMP Echo"
  }

  ingress {
    from_port   = 4420
    to_port     = 4420
    protocol    = "tcp"
    self        = true
    description = "storage nodes discovery"
  }

  ingress {
    from_port   = 9100
    to_port     = 9900
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "storage node lvol connect"
  }

  ingress {
    from_port   = 9060
    to_port     = 9099
    protocol    = "tcp"
    self        = true
    description = "storage node remote devices"
  }

  ingress {
    from_port   = 9030
    to_port     = 9060
    protocol    = "tcp"
    self        = true
    description = "storage node hubLvol"
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id, aws_security_group.extra_nodes_sg.id]
    description     = "access SNodeAPI from mgmt and k3s nodes"
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    self            = true
    description     = "access SNodeAPI from snode node workers"
  }

  ingress {
    from_port   = 12201
    to_port     = 12201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Graylog GELF Communication TCP"
  }

  ingress {
    from_port   = 12201
    to_port     = 12201
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Graylog GELF Communication TCP"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow traffic from API gateway to Mgmt nodes"
  }
}

module "eks" {
  count   = var.enable_eks
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${terraform.workspace}-${var.cluster_name}"
  cluster_version = "1.33"

  cluster_endpoint_private_access = true # default is true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_group_defaults = {
    disk_size                  = 30
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {

    # bottlerock storage nodes
    bottlerocket = {
      instance_types             = ["m6id.large"]
      ami_type                   = "BOTTLEROCKET_x86_64"
      capacity_type              = "ON_DEMAND"
      use_custom_launch_template = false
      vpc_security_group_ids     = [aws_security_group.eks_nodes_sg[0].id]
      min_size                   = 0
      max_size                   = 3
      desired_size               = 0
      key_name                   = local.selected_key_name
      enable_bootstrap_user_data = true
      remote_access = {
        ec2_ssh_key = local.selected_key_name
        source_security_group_ids = [aws_security_group.eks_nodes_sg[0].id]
      }
      # This will get added to the template
      bootstrap_extra_args = <<-EOT
        # The admin host container provides SSH access and runs with "superpowers".
        # It is disabled by default, but can be disabled explicitly.
        [settings.host-containers.admin]
        enabled = true

        # The control host container provides out-of-band access via SSM.
        # It is enabled by default, and can be disabled if you do not expect to use SSM.
        # This could leave you with no way to access the API and change settings on an existing node!
        [settings.host-containers.control]
        enabled = true

        # extra args added
        [settings.kernel]
        lockdown = "integrity"

        [settings.kubernetes.node-labels]
        "io.simplyblock.node-type" = "simplyblock-storage-plane"

        [settings.kubernetes.node-taints]
        dedicated = "experimental:PreferNoSchedule"
        special = "true:NoSchedule"
      EOT

      pre_bootstrap_user_data = <<-EOT
        echo "installing nvme-cli.."
        sudo yum install -y nvme-cli
        sudo modprobe nvme-tcp
      EOT
    }

    # AL2023 storage nodes
    # TODO: add support for ARM images
    al2023 = {
      desired_size = var.storage_nodes
      min_size     = 3
      max_size     = 10

      labels = {
        "io.simplyblock.node-type" = "simplyblock-storage-plane"
      }

      ami_type                = "AL2023_x86_64_STANDARD"
      instance_types          = [var.storage_nodes_instance_type]
      architecture             = var.storage_nodes_arch
      capacity_type           = "ON_DEMAND"
      key_name                = local.selected_key_name
      vpc_security_group_ids  = [aws_security_group.eks_nodes_sg[0].id]
      bootstrap_extra_args = <<-EOT
        # The admin host container provides SSH access and runs with "superpowers".
        # It is disabled by default, but can be disabled explicitly.
        [settings.host-containers.admin]
        enabled = true

        # The control host container provides out-of-band access via SSM.
        # It is enabled by default, and can be disabled if you do not expect to use SSM.
        # This could leave you with no way to access the API and change settings on an existing node!
        [settings.host-containers.control]
        enabled = true

        # extra args added
        [settings.kernel]
        lockdown = "integrity"

        [settings.kubernetes.node-labels]
        type = "simplyblock-storage-plane"
      EOT
      pre_bootstrap_user_data = <<-EOT
        echo "installing nvme-cli.."
        sudo yum install -y nvme-cli
        sudo modprobe nvme-tcp
        sudo dnf install tuned
      EOT
    }
  }

  tags = {
    Name        = "${terraform.workspace}-${var.cluster_name}"
    Environment = "${terraform.workspace}-dev"
  }
}


resource "aws_eks_access_entry" "user1" {
  cluster_name      = "${terraform.workspace}-${var.cluster_name}"
  principal_arn     = data.aws_caller_identity.current.arn
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "eksclusteradmin" {
  cluster_name  = "${terraform.workspace}-${var.cluster_name}"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type       = "cluster"
  }
}
