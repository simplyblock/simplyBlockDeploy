
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${terraform.workspace}-storage-vpc-sb"
  cidr = "10.0.0.0/16"

  azs                     = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1], ]
  private_subnets         = ["10.0.1.0/24", "10.0.3.0/24"]
  public_subnets          = ["10.0.2.0/24", "10.0.4.0/24"]
  map_public_ip_on_launch = true

  enable_nat_gateway = true

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
    Environment = "${terraform.workspace}-dev"
    # long-term-test = "true"
  }
}

module "apigatewayendpoint" {
  count                 = var.enable_apigateway == 1 && var.mgmt_nodes > 0 ? 1 : 0
  source                = "./modules/apigateway"
  region                = var.region
  mgmt_node_instance_id = aws_instance.mgmt_nodes[0].id
  mgmt_node_private_ip  = aws_instance.mgmt_nodes[0].private_ip
  container_inst_sg_id  = aws_security_group.container_inst_sg.id
  public_subnets        = module.vpc.public_subnets
}

resource "aws_security_group" "container_inst_sg" {
  name        = "${terraform.workspace}-container-instance-sg"
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
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "graylog security group"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    self      = true
  }

  ## Egress traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "mgmt_api" {
  count = var.enable_apigateway == 0 ? 1 : 0

  security_group_id = aws_security_group.container_inst_sg.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "grafana_api" {
  count = var.enable_apigateway == 0 ? 1 : 0

  security_group_id = aws_security_group.container_inst_sg.id
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
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
  name        = "${terraform.workspace}-codeartifact_policy_policy"
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

resource "aws_instance" "bastion" {
  ami                    = local.region_ami_map[var.region] # RHEL 9
  instance_type          = "t2.micro"
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "${terraform.workspace}-bastion"
  }
}

resource "aws_instance" "mgmt_nodes" {
  count                  = var.mgmt_nodes
  ami                    = local.region_ami_map[var.region] # RHEL 9
  instance_type          = var.mgmt_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.private_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 100
  }
  tags = {
    Name = "${terraform.workspace}-mgmt-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
echo "installing sbcli.."
sudo  yum install -y pip jq
pip install ${var.sbcli_pkg}

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
  for_each = local.snodes

  ami                    = local.region_ami_map[var.region] # RHEL 9
  instance_type          = var.storage_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.private_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "${terraform.workspace}-storage-${each.value + 1}"
  }
  user_data = <<EOF
#!/bin/bash
sudo sysctl -w vm.nr_hugepages=${var.nr_hugepages}
cat /proc/meminfo | grep -i hug
echo "installing sbcli.."
sudo yum install -y pip unzip
pip install ${var.sbcli_pkg}
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
${var.sbcli_pkg} storage-node deploy
EOF
}

resource "aws_ebs_volume" "storage_nodes_ebs" {
  count             = var.volumes_per_storage_nodes > 0 ? var.storage_nodes : 0
  availability_zone = data.aws_availability_zones.available.names[1]
  size              = var.storage_nodes_ebs_size1
}

resource "aws_ebs_volume" "storage_nodes_ebs2" {
  for_each = local.node_disks

  availability_zone = data.aws_availability_zones.available.names[1]
  size              = var.storage_nodes_ebs_size2
}

resource "aws_volume_attachment" "attach_sn2" {
  for_each = local.node_disks

  device_name = each.value.disk_dev_path
  volume_id   = aws_ebs_volume.storage_nodes_ebs2[each.key].id
  instance_id = aws_instance.storage_nodes[each.value.node_name].id
}

resource "aws_volume_attachment" "attach_sn" {
  count       = var.volumes_per_storage_nodes > 0 ? var.storage_nodes : 0
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.storage_nodes_ebs[count.index].id
  instance_id = aws_instance.storage_nodes[count.index].id
}

# can be used for testing caching nodes
resource "aws_instance" "extra_nodes" {
  count                  = var.extra_nodes
  ami                    = local.region_ami_map[var.region] # RHEL 9
  instance_type          = var.extra_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.container_inst_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 25
  }
  tags = {
    Name = "${terraform.workspace}-k8scluster-${count.index + 1}"
  }
  user_data = <<EOF
#!/bin/bash
sudo sysctl -w vm.nr_hugepages=${var.nr_hugepages}
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

  cluster_name    = "${terraform.workspace}-${var.cluster_name}"
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
    Name        = "${terraform.workspace}-${var.cluster_name}"
    Environment = "${terraform.workspace}-dev"
  }
}
