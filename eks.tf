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
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow traffic from API gateway to Mgmt nodes"
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
  }

  eks_managed_node_groups = {
    eks-nodes = {
      desired_size = 1
      min_size     = 1
      max_size     = 4

      labels = {
        role = "general"
      }

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

      instance_types          = ["i3en.large"]
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
