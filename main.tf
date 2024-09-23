
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
  count                  = var.enable_apigateway == 1 && var.mgmt_nodes > 0 ? 1 : 0
  source                 = "./modules/apigateway"
  region                 = var.region
  mgmt_node_instance_ids = aws_instance.mgmt_nodes[*].id
  api_gateway_id         = aws_security_group.api_gateway_sg.id
  loadbalancer_id        = aws_security_group.loadbalancer_sg.id
  public_subnets         = module.vpc.public_subnets
  vpc_id                 = module.vpc.vpc_id
}


resource "aws_security_group" "api_gateway_sg" {
  name        = "${terraform.workspace}-api_gateway_sg"
  description = "API Gateway Security Group"

  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow traffic from API gateway to Loadbalancer"
  }
}

resource "aws_security_group" "loadbalancer_sg" {
  name        = "${terraform.workspace}-loadbalancer_sg"
  description = "Loadbalancer Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway_sg.id]
    description     = "HTTP from API gateway"
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway_sg.id]
    description     = "Grafana from API gateway"
  }

  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway_sg.id]
    description     = "Graylog from API gateway"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow traffic from API gateway to Mgmt nodes"
  }
}


resource "aws_security_group" "mgmt_node_sg" {
  name        = "${terraform.workspace}-mgmt_node_sg"
  description = "CSI Cluster Container Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
    description = "EFS from mgmt nodes"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "SSH from Bastion Server"
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancer_sg.id]
    description     = "HTTP from Loadbalancer"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = true
    description = "HTTP from other mgmt nodes"
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancer_sg.id]
    description     = "Grafana from Loadbalancer"
  }

  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancer_sg.id]
    description     = "Graylog from Loadbalancer"
  }

  ingress {
    from_port   = 2375
    to_port     = 2375
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "docker engine API"
  }

  # Docker Swarm Manager Ports: start
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Manager Communication"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Node Communication TCP"
  }

  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Node Communication UDP"
  }

  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Overlay Network"
  }

  # Graylog GELF
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

  # end

  # fdb
  ingress {
    from_port   = 4800
    to_port     = 4800
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "all output traffic so that packages can be downloaded"
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    self        = true
    description = "allow ICMP Echo"
  }
}

resource "aws_security_group" "storage_nodes_sg" {
  name        = "${terraform.workspace}-storage_nodes_sg"
  description = "CSI Cluster Container Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 4420
    to_port     = 4420
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "storage node lvol connect"
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
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
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.extra_nodes_sg.id]
    description     = "access SNodeAPI from k3s nodes"
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "For SPDK Proxy for the storage node from mgmt node"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
    description = "For SPDK Proxy for the storage node from other storage nodes"
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
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_node_sg.id]
    description     = "prometheus scrape from mgmt nodes"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
    description     = "SSH from Bastion Server"
  }

  # Docker Swarm Ports: start
  ingress {
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Manager Communication"
  }
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Node Communication TCP"
  }
  ingress {
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Node Communication UDP"
  }

  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Docker Swarm Overlay Network"
  }

  # Graylog GELF
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

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "k3s cluster"
  }

  ingress {
    from_port   = 10250
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "k8s node communication"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow DNS resolution from worker nodes"
  }

  ingress {
    from_port   = 1025
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow UDP traffic on ephemeral ports"
  }

  # end

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
    description = "all output traffic so that packages can be downloaded"
  }
}

resource "aws_security_group" "extra_nodes_sg" {
  name        = "${terraform.workspace}-extra_nodes_sg"
  description = "CSI Cluster Container Security Group"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = "k3s cluster"
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
    description = "k3s cluster"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }

  ingress {
    from_port   = 10250
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "k8s node communication"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow DNS resolution from worker nodes"
  }

  ingress {
    from_port   = 1025
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow UDP traffic on ephemeral ports"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "${terraform.workspace}-bastion_sg"
  description = "CSI Cluster Container Security Group"

  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist_ips
    description = ""
  }
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
resource "aws_iam_policy" "mgmt_policy" {
  name        = "${terraform.workspace}-mgmt_node_policy"
  description = "Policy for allowing EC2 to communicate with other resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeTags"
        ],
        "Resource" : "*"
      },
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
      {
        Action = [
          "ssm:SendCommand",
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:ec2:${var.region}:${local.account_id}:instance/*",
          "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
          "arn:aws:ssm:${var.region}:${local.account_id}:*"
        ]
      },
      {
        Action = [
          "ssm:GetCommandInvocation"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:ssm:${var.region}:${local.account_id}:*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.tfengine_logs.arn}/*",
          "arn:aws:s3:::${var.tf_state_bucket_name}/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::${var.tf_state_bucket_name}"
        ]
      }
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
  policy_arn = aws_iam_policy.mgmt_policy.arn
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
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  subnet_id              = module.vpc.public_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 45
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
  vpc_security_group_ids = [aws_security_group.mgmt_node_sg.id]
  subnet_id              = module.vpc.private_subnets[local.az_index]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 100
  }
  tags = {
    Name = "${terraform.workspace}-mgmt-${count.index + 1}"
  }

  lifecycle {
    ignore_changes = [
      subnet_id,
    ]
  }

  user_data = <<EOF
#!/bin/bash
echo "installing sbcli.."
sudo  yum install -y pip jq
pip install ${local.sbcli_pkg}

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

  ami                    = local.ami_map[var.storage_nodes_arch][var.region] # RHEL 9
  instance_type          = var.storage_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.storage_nodes_sg.id]
  subnet_id              = module.vpc.private_subnets[local.az_index]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 45
  }
  tags = {
    Name = "${terraform.workspace}-storage-${each.value + 1}"
  }

  lifecycle {
    ignore_changes = [
      subnet_id,
    ]
  }

  user_data = <<EOF
#!/bin/bash
sudo sysctl -w vm.nr_hugepages=${var.nr_hugepages}
cat /proc/meminfo | grep -i hug
echo "installing sbcli.."
sudo yum install -y pip unzip
pip install ${local.sbcli_pkg}
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
if [ "${var.snode_deploy_on_k8s}" = "false" ]; then
  ${var.sbcli_cmd} storage-node deploy
fi
EOF
}

resource "aws_ebs_volume" "storage_nodes_ebs" {
  count             = var.volumes_per_storage_nodes > 0 && var.storage_nodes > 0 ? var.storage_nodes : 0
  availability_zone = data.aws_availability_zones.available.names[local.az_index]
  size              = var.storage_nodes_ebs_size1

  lifecycle {
    ignore_changes = [
      availability_zone,
    ]
  }
}

resource "aws_ebs_volume" "storage_nodes_ebs2" {
  for_each = var.storage_nodes > 0 ? local.node_disks : {}

  availability_zone = data.aws_availability_zones.available.names[local.az_index]
  size              = var.storage_nodes_ebs_size2

  lifecycle {
    ignore_changes = [
      availability_zone,
    ]
  }
}

resource "aws_volume_attachment" "attach_sn2" {
  for_each = var.storage_nodes > 0 ? local.node_disks : {}

  device_name = each.value.disk_dev_path
  volume_id   = aws_ebs_volume.storage_nodes_ebs2[each.key].id
  instance_id = aws_instance.storage_nodes[each.value.node_name].id
}

resource "aws_volume_attachment" "attach_sn" {
  count       = var.volumes_per_storage_nodes > 0 && var.storage_nodes > 0 ? var.storage_nodes : 0
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.storage_nodes_ebs[count.index].id
  instance_id = aws_instance.storage_nodes[count.index].id
}

# can be used for testing caching nodes
resource "aws_instance" "extra_nodes" {
  count                  = var.extra_nodes
  ami                    = local.ami_map[var.extra_nodes_arch][var.region] # RHEL 9
  instance_type          = var.extra_nodes_instance_type
  key_name               = local.selected_key_name
  vpc_security_group_ids = [aws_security_group.extra_nodes_sg.id]
  subnet_id              = module.vpc.public_subnets[1]
  iam_instance_profile   = aws_iam_instance_profile.inst_profile.name
  root_block_device {
    volume_size = 45
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
