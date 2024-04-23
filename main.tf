provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket         = "simplyblock-terraform-state-bucket"
    key            = "csi"
    region         = "us-east-2"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {

  snodes = toset([for n in range(var.storage_nodes) : tostring(n)])

  node_disks = { for pair in setproduct(local.snodes, slice(var.volume_device_names,0,var.volumes_per_storage_nodes)) : "${pair[0]}:${pair[1]}" => {
  node_name     = pair[0]
  disk_dev_path = pair[1]
  } }

  key_name = {
    "us-east-1" = "simplyblock-us-east-1.pem"
    "us-east-2" = "simplyblock-us-east-2.pem"
  }

  selected_key_name = try(local.key_name[var.region], "simplyblock-us-east-2.pem")
}

data "aws_secretsmanager_secret_version" "simply" {
  secret_id = local.selected_key_name
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.namespace}-storage-vpc-sb"
  cidr = "10.0.0.0/16"

  azs                     = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1], ]
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
    Environment = "${var.namespace}-dev"
  }
}

resource "aws_security_group" "container_inst_sg" {
  name        = "${var.namespace}-container-instance-sg"
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
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "k3s cluster"
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
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "graylog security group"
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "grafana security group"
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

# create assumed role
data "aws_iam_policy_document" "assume_role_policy" {

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole",
    ]
  }
}

# create a policy
resource "aws_iam_policy" "codeartifact_policy" {
  name        = "codeartifact_policy_policy"
  description = "Policy for allowing EC2 to get objects from codeartifact"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : "sts:GetServiceBearerToken",
        "Resource" : "*"
      },
      {
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository",
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:codeartifact:eu-west-1:565979732541:repository/simplyblock/sbcli",
          "arn:aws:codeartifact:eu-west-1:565979732541:domain/simplyblock"
        ]
      },
    ]
  })
}

# create a role with an assumed policy
resource "aws_iam_role" "role" {
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

# attach policy to the role
resource "aws_iam_role_policy_attachment" "s3_get_object_attachment" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.codeartifact_policy.arn
}

# create instance profile
resource "aws_iam_instance_profile" "inst_profile" {
  name = "simplyblock-instance-profile-${terraform.workspace}"
  role = aws_iam_role.role.name
}

resource "aws_instance" "mgmt_nodes" {
  count                  = var.mgmt_nodes
  ami                    = var.region_ami_map[var.region] # RHEL 9
  instance_type          = var.mgmt_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 100
  }
  tags = {
    Name = "${var.namespace}-mgmt-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
echo "installing sbcli.."
sudo  yum install -y pip jq
pip install sbcli-dev

sudo yum install -y fio nvme-cli unzip;
sudo modprobe nvme-tcp
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
EOF
}

resource "aws_instance" "storage_nodes" {
  for_each               = local.snodes
  
  ami                    = var.region_ami_map[var.region] # RHEL 9
  instance_type          = var.storage_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "${var.namespace}-storage-${each.value + 1}"
  }
  user_data = <<EOF
#!/bin/bash
sudo sysctl -w vm.nr_hugepages=2048
cat /proc/meminfo | grep -i hug
echo "installing sbcli.."
sudo yum install -y pip unzip
pip install sbcli-dev
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
sbcli-dev storage-node deploy
EOF
}

resource "aws_ebs_volume" "storage_nodes_ebs" {
  count             = var.storage_nodes
  availability_zone = data.aws_availability_zones.available.names[1]
  size              = var.storage_nodes_ebs_size1
}

resource "aws_ebs_volume" "storage_nodes_ebs2" {
  for_each          = local.node_disks

  availability_zone = data.aws_availability_zones.available.names[1]
  size              = var.storage_nodes_ebs_size2
}

resource "aws_volume_attachment" "attach_sn2" {
  for_each    = local.node_disks

  device_name = each.value.disk_dev_path
  volume_id   = aws_ebs_volume.storage_nodes_ebs2[each.key].id
  instance_id = aws_instance.storage_nodes[each.value.node_name].id
}

resource "aws_volume_attachment" "attach_sn" {
  count       = var.storage_nodes
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.storage_nodes_ebs[count.index].id
  instance_id = aws_instance.storage_nodes[count.index].id
}

# can be used for testing caching nodes
resource "aws_instance" "extra_nodes" {
  count                  = var.extra_nodes
  ami                    = var.region_ami_map[var.region] # RHEL 9
  instance_type          = var.extra_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "${var.namespace}-k8scluster-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
sudo sysctl -w vm.nr_hugepages=2048
cat /proc/meminfo | grep -i hug
EOF
}


# resource "aws_ebs_volume" "extra_nodes_ebs" {
#   count             = var.extra_nodes
#   availability_zone = "us-east-2b"
#   size              = 50
# }

# resource "aws_volume_attachment" "attach_cn" {
#   count       = var.extra_nodes
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.extra_nodes_ebs[count.index].id
#   instance_id = aws_instance.extra_nodes[count.index].id
# }


################################################################################
# EKS
################################################################################
module "eks" {
  count   = var.enable_eks
  source  = "terraform-aws-modules/eks/aws"
  version = "19.16.0"

  cluster_name    = "${var.namespace}-${var.cluster_name}"
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
      desired_size = 1
      min_size     = 1
      max_size     = 4

      labels = {
        role = "general"
      }

      instance_types          = ["t3.large"]
      capacity_type           = "ON_DEMAND"
      key_name                = local.selected_key_name
      vpc_security_group_ids  = [aws_security_group.container_inst_sg.id]
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
      vpc_security_group_ids  = [aws_security_group.container_inst_sg.id]
      pre_bootstrap_user_data = <<-EOT
        echo "installing nvme-cli.."
        sudo yum install -y nvme-cli
        sudo modprobe nvme-tcp
      EOT
    }
  }

  tags = {
    Name        = "${var.namespace}-${var.cluster_name}"
    Environment = "${var.namespace}-dev"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "storage_private_ips" {
  value = join(" ", [for inst in aws_instance.storage_nodes : inst.private_ip])
}

output "storage_public_ips" {
  value = join(" ", [for inst in aws_instance.storage_nodes : inst.public_ip])
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
  value = join(" ", aws_instance.extra_nodes[*].public_ip)
}

output "key_name" {
  value = local.selected_key_name
}
output "secret_value" {
  sensitive = true
  value     = data.aws_secretsmanager_secret_version.simply.secret_string
}
