
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

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
  count                  = var.mgmt_nodes > 0 ? 1 : 0
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
    from_port   = 12202
    to_port     = 12202
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Graylog GELF Communication TCP"
  }

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
    security_groups = [aws_security_group.bastion_sg.id,aws_security_group.mgmt_node_sg.id]
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


# create a role with an assumed policy
resource "aws_iam_role" "role" {
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}


# create instance profile
resource "aws_iam_instance_profile" "inst_profile" {
  name = "simplyblock-instance-profile-${terraform.workspace}"
  role = aws_iam_role.role.name
}

resource "aws_instance" "bastion" {
  ami                    = local.region_ami_map[var.region] # RHEL 9 // use this outside simplyblock aws acccount data.aws_ami.rhel9.id
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
  user_data = <<EOF
#!/bin/bash
echo "${file(pathexpand(var.ssh_key_path))}" >> /home/ec2-user/.ssh/authorized_keys
EOF
}

resource "aws_instance" "mgmt_nodes" {
  count                  = var.mgmt_nodes
  ami                    = local.region_ami_map[var.region] # RHEL 9 // use this outside simplyblock aws acccount data.aws_ami.rhel9.id
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
echo "${file(pathexpand(var.ssh_key_path))}" >> /home/ec2-user/.ssh/authorized_keys
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

  ami                    = local.ami_map[var.storage_nodes_arch][var.region] # RHEL 9 // use this outside simplyblock aws acccount data.aws_ami.rhel9.id
  instance_type          = var.storage_nodes_instance_type
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
echo "${file(pathexpand(var.ssh_key_path))}" >> /home/ec2-user/.ssh/authorized_keys
sudo sysctl -w vm.nr_hugepages=${var.nr_hugepages}
cat /proc/meminfo | grep -i hug
echo "installing sbcli.."
sudo yum install -y pip unzip
pip install ${local.sbcli_pkg}
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
  ${var.sbcli_cmd} storage-node configure --max-lvol ${var.max_lvol} --max-size ${var.max_size} \
                --nodes-per-socket ${var.nodes_per_socket} --sockets-to-use ${var.socket_to_use} \
                --pci-allowed "${join(",", var.pci_allowed)}" --pci-blocked "${join(",", var.pci_blocked)}"

  ${var.sbcli_cmd} storage-node deploy
EOF
}
