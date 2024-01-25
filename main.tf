provider "aws" {
  region = "us-east-2"
}

terraform {
  backend "s3" {
    bucket = "simplyblock-terraform-state-bucket"
    key    = "csi"
    region = "us-east-2"
    # dynamodb_table = "terraform-up-and-running-locks"
    encrypt = true
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "sb-storage-vpc"
  cidr = "10.0.0.0/16"

  azs                     = ["us-east-2a", "us-east-2b", ]
  private_subnets         = ["10.0.1.0/24", "10.0.3.0/24"]
  public_subnets          = ["10.0.2.0/24", "10.0.4.0/24"]
  map_public_ip_on_launch = true

  enable_nat_gateway = false

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "container_inst_sg" {
  name        = "container-instance-sg"
  description = "CSI Cluster Container Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5900
    to_port     = 5909
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "VNC from world"
  }
  ingress {
    from_port   = 8404
    to_port     = 8404
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
  # all traffic from 172.30.0.0/16
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    self      = true
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = ""
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = ""
  }
  ingress {
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }


  ## Egress traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mgmt_nodes" {
  count                  = var.mgmt_nodes
  ami                    = "ami-0ef50c2b2eb330511" # RHEL 9
  instance_type          = "t3.large"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  root_block_device {
    volume_size = 100
  }
  tags = {
    Name = "mgmt-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
echo "installing sbcli.."
sudo  yum install -y pip jq
pip install sbcli

sudo yum install -y fio nvme-cli;
sudo modprobe nvme-tcp
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

EOF
}

resource "aws_instance" "storage_nodes" {
  count                  = var.storage_nodes
  ami                    = "ami-0ef50c2b2eb330511" # RHEL 9
  instance_type          = "t3.large"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "storage-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
echo "installing sbcli.."
sudo yum install -y pip
pip install sbcli
sbcli storage-node deploy
EOF
}

resource "aws_ebs_volume" "storage_nodes_ebs" {
  count             = var.storage_nodes
  availability_zone = "us-east-2b"
  size              = 50
}

resource "aws_volume_attachment" "attach_sn" {
  count       = var.storage_nodes
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.storage_nodes_ebs[count.index].id
  instance_id = aws_instance.storage_nodes[count.index].id
}

resource "aws_instance" "extra_nodes" {
  count                  = var.extra_nodes
  ami                    = "ami-0ef50c2b2eb330511" # RHEL 9
  instance_type          = "t3.large"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "k8scluster-${count.index + 1}"
  }
}

resource "aws_ebs_volume" "extra_nodes_ebs" {
  count             = var.extra_nodes
  availability_zone = "us-east-2b"
  size              = 50
}

resource "aws_volume_attachment" "attach_cn" {
  count       = var.extra_nodes
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.extra_nodes_ebs[count.index].id
  instance_id = aws_instance.extra_nodes[count.index].id
}


################################################################################
# EKS
################################################################################
module "eks" {
  count   = var.enable_eks
  source  = "terraform-aws-modules/eks/aws"
  version = "19.16.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

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
      desired_size = 3
      min_size     = 2
      max_size     = 4

      labels = {
        role = "general"
      }

      instance_types                       = ["t3.medium"]
      capacity_type                        = "ON_DEMAND"
      key_name                             = "simplyblock-us-east-2.pem"
      worker_additional_security_group_ids = [aws_security_group.container_inst_sg.id]
    }

    # cache-nodes = {
    #   desired_size = 1
    #   min_size     = 1
    #   max_size     = 1
    #   ami_id = "ami-0ef50c2b2eb330511"
    #   instance_types = ["i4i.large"]
    #   capacity_type                        = "ON_DEMAND"
    #   key_name                             = "simplyblock-us-east-2.pem"
    #   worker_additional_security_group_ids = [aws_security_group.container_inst_sg.id]
    # }
  }

  tags = {
    Name        = "simplyblock-eks-cluster"
    Environment = "dev"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "storage_private_ips" {
  value = join(" ", aws_instance.storage_nodes[*].private_ip)
}

output "mgmt_private_ips" {
  value = aws_instance.mgmt_nodes[*].private_ip
}

output "mgmt_public_ips" {
  value = join(" ", aws_instance.mgmt_nodes[*].public_ip)
}

output "extra_nodes_private_ips" {
  value = aws_instance.extra_nodes[*].private_ip
}

output "extra_nodes_public_ips" {
  value = aws_instance.extra_nodes[*].public_ip
}
