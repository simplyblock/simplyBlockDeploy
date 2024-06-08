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
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "For SPDK Proxy for the storage node"
  }

  ingress {
    from_port       = 2375
    to_port         = 2375
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "docker engine API"
  }

  ingress {
    from_port       = 8
    to_port         = 0
    protocol        = "icmp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "allow ICMP Echo"
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "caching node"
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
  version = "19.16.0"

  cluster_name    = "${terraform.workspace}-${var.cluster_name}"
  cluster_version = "1.30"

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

  enable_irsa = true

  eks_managed_node_group_defaults = {
    disk_size                  = 30
    iam_role_attach_cni_policy = true
    remote_access = {
      ec2_ssh_key               = local.selected_key_name
      source_security_group_ids = [aws_security_group.eks_nodes_sg[0].id]
    }
  }

  eks_managed_node_groups = {

    # FIXME: Caching-node not working properly with bottlerocket ami_type
    # https://simplyblock.atlassian.net/browse/SFAM-865

    bottlerocket = {
      instance_types             = ["m6id.large"]
      ami_type                   = "BOTTLEROCKET_x86_64"
      capacity_type              = "ON_DEMAND"
      use_custom_launch_template = false
      vpc_security_group_ids     = [aws_security_group.eks_nodes_sg[0].id]
      min_size                   = 0
      max_size                   = 1
      desired_size               = 0
      key_name                   = local.selected_key_name
      enable_bootstrap_user_data = true
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
        label1 = "foo"
        label2 = "bar"

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

    eks-nodes = {
      desired_size = 1
      min_size     = 1
      max_size     = 2

      labels = {
        role = "general"
      }

      ami_type                = "AL2_x86_64"
      instance_types          = ["t3.large"]
      capacity_type           = "ON_DEMAND"
      key_name                = local.selected_key_name
      vpc_security_group_ids  = [aws_security_group.eks_nodes_sg[0].id]
      pre_bootstrap_user_data = <<-EOT
        echo "installing nvme-cli.."
        sudo yum install -y nvme-cli
        sudo modprobe nvme-tcp
      EOT
    }

    cache-nodes = {
      desired_size = 2
      min_size     = 2
      max_size     = 3
      labels = {
        role = "cache"
      }

      ami_type                = "AL2_x86_64"
      instance_types          = ["m6id.large"]
      capacity_type           = "ON_DEMAND"
      key_name                = local.selected_key_name
      vpc_security_group_ids  = [aws_security_group.eks_nodes_sg[0].id]
      pre_bootstrap_user_data = <<-EOT
        echo "installing nvme-cli.."
        sudo yum install -y nvme-cli
        sudo modprobe nvme-tcp
      EOT
    }
  }

  tags = {
    Name        = "${terraform.workspace}-${var.cluster_name}"
    Environment = "${terraform.workspace}-dev"
  }
}
