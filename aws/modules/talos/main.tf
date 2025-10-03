data "aws_availability_zones" "available" {
  state = "available"
}

# # Fetch Talos cloud-images.json for the release and parse it to get AMI for region
data "http" "talos_cloud_images" {
  url = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/cloud-images.json"
}

locals {
  talos_images = jsondecode(data.http.talos_cloud_images.response_body)
  talos_ami = (
    [for img in local.talos_images :
      img if img.region == var.aws_region && img.arch == "amd64"
    ][0]
  ).id
}

# Security group: allow Talos, Kubernetes API, Wireguard (KubeSpan) per the guide
resource "aws_security_group" "talos_sg" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for Talos cluster (control plane + workers)"
  vpc_id      = var.vpc_id

  # Allow Talos API (port 50000) from anywhere (tutorial)
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Talos API"
  }

  # Kubernetes API (port 6443) for the NLB to target
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API"
  }

  # Wireguard UDP (kubespan) - tutorial opens UDP 51820
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "KubeSpan / Wireguard"
  }

  # Allow all inside SG (instances talking to each other)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "allow intra-sg"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-sg" }
}

resource "aws_eip" "cp_eip" {
  tags = {
    Name = "${var.cluster_name}-cp-eip"
  }
}

data "external" "talos_configs" {
  program = [
    "python3",
    "-c",
    <<PY
import base64
import json
import os
import subprocess
import sys


def fail(message: str) -> None:
    json.dump({"error": message}, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(1)


try:
    params = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    fail(f"invalid input JSON: {exc}")

endpoint = params.get("endpoint")
cluster = params.get("cluster") or "talos-k8s"
module_dir = params.get("module_dir")

if not endpoint:
    fail("endpoint is not available yet")

if not module_dir:
    fail("module_dir not provided")

patch_path = os.path.join(module_dir, "machine-patch.yaml")
output_dir = os.path.join(module_dir, "generated")
os.makedirs(output_dir, exist_ok=True)

cmd = [
    "talosctl",
    "gen",
    "config",
    cluster,
    f"https://{endpoint}:6443",
    "--with-examples=false",
    "--with-docs=false",
    "--with-kubespan",
    "--install-disk",
    "/dev/xvda",
    "--output",
    output_dir,
    "--config-patch",
    f"@{patch_path}",
    "--force",
]

try:
    subprocess.run(cmd, check=True, capture_output=True, text=True)
except FileNotFoundError:
    fail("talosctl binary not found in PATH")
except subprocess.CalledProcessError as exc:
    details = exc.stderr.strip() or exc.stdout.strip() or str(exc)
    fail(f"talosctl failed: {details}")


def encode(path: str) -> str:
    with open(path, "rb") as handle:
        return base64.b64encode(handle.read()).decode()


result = {
    "controlplane": encode(os.path.join(output_dir, "controlplane.yaml")),
    "worker": encode(os.path.join(output_dir, "worker.yaml")),
    "talosconfig_path": os.path.join(output_dir, "talosconfig"),
}

json.dump(result, sys.stdout)
sys.stdout.write("\n")
PY
  ]

  query = {
    endpoint   = aws_eip.cp_eip.public_ip
    cluster    = var.cluster_name
    module_dir = path.module
  }

  depends_on = [aws_eip.cp_eip]
}

resource "aws_instance" "control_plane" {
  count                       = 1
  ami                         = local.talos_ami
  instance_type               = var.control_plane_instance_type
  subnet_id                   = var.public_subnets[count.index % length(var.public_subnets)]
  vpc_security_group_ids      = [aws_security_group.talos_sg.id, var.storage_node_sg]
  associate_public_ip_address = true
  user_data_base64            = data.external.talos_configs.result.controlplane
  tags = {
    Name = "${var.cluster_name}-cp-${count.index}"
    Role = "control-plane"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [user_data_base64]
  }
  depends_on = [data.external.talos_configs]
}

resource "aws_eip_association" "cp_eip_assoc" {
  instance_id   = aws_instance.control_plane[0].id
  allocation_id = aws_eip.cp_eip.id
}

resource "aws_launch_template" "worker_lt" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = local.talos_ami
  instance_type = var.worker_instance_type

  network_interfaces {
    security_groups             = [aws_security_group.talos_sg.id, var.storage_node_sg]
    associate_public_ip_address = true
  }

  user_data  = data.external.talos_configs.result.worker
  depends_on = [data.external.talos_configs]
}

resource "aws_autoscaling_group" "workers" {
  name                = "${var.cluster_name}-workers"
  max_size            = var.worker_desired_capacity + 1
  min_size            = max(1, var.worker_desired_capacity)
  desired_capacity    = var.worker_desired_capacity
  vpc_zone_identifier = var.public_subnets
  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }
}

# Outputs
output "talos_ami" {
  value = local.talos_ami
}

output "cp_ip_addresses" {
  value = aws_eip.cp_eip.public_ip
}

output "control_plane_instance_ids" {
  value = [for i in aws_instance.control_plane : i.id]
}

output "talos_config_path" {
  value = data.external.talos_configs.result.talosconfig_path
}
