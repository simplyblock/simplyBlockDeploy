data "aws_caller_identity" "current" {}

locals {
  volume_device_names = ["/dev/sdi", "/dev/sdj", "/dev/sdk", "/dev/sdl", "/dev/sdm", "/dev/sdn", "/dev/sdo"]

  snodes = toset([for n in range(var.storage_nodes) : tostring(n)])

  key_name = {
    "us-east-1"  = "simplyblock-us-east-1.pem"
    "us-east-2"  = "simplyblock-us-east-2.pem"
    "eu-north-1" = "simplyblock-eu-north-1.pem"
    "eu-west-1"  = "simplyblock-eu-west-1.pem"
  }

  selected_key_name = try(local.key_name[var.region], "simplyblock-us-east-2.pem")

# Images are generated from this image builder:
# https://us-east-2.console.aws.amazon.com/imagebuilder/home?region=us-east-2#/pipelines/arn:aws:imagebuilder:us-east-2:565979732541:image-pipeline/tst
#
# it is basically rhel9 + the following lines:
#  $sudo yum update -y
#  $sudo yum install -y yum-utils xorg-x11-xauth nvme-cli fio
  region_ami_map_rhel9 = {
    "us-east-1"  = "ami-0ff9547ee3e11637a"
    "us-east-2"  = "ami-00b0bb86a4287f38f"
    "eu-north-1" = "ami-01997ffb7707167a4"
    "eu-west-1"  = "ami-0a3bac9371ffc12f8"
  }

  region_ami_map_rhel10 = {
    "us-east-1"  = "ami-0fd3ac4abb734302a"
    "us-east-2"  = "ami-0f70b01eb0d5c5caa"
    "eu-north-1" = "ami-09627188d1e477c9e"
    "eu-west-1"  = "ami-0ae53736fc234deff"
  }

  region_ami_map_ubuntu24 = {
    "us-east-1"  = "ami-0360c520857e3138f"
    "us-east-2"  = "ami-0cfde0ea8edd312d4"
    "eu-north-1" = "ami-0a716d3f3b16d290c"
    "eu-west-1"  = "ami-0d71ea34b358e5e74"
  }

  region_ami_map_ubuntu22 = {
    "us-east-1"  = "ami-0bbdd8c17ed981ef9"
    "us-east-2"  = "ami-0d9a665f802ae6227"
    "eu-north-1" = "ami-07e075f00c26b085a"
    "eu-west-1"  = "ami-0a563f173f6b97b04"
  }

  region_ami_map_rhel9_arm = {
    "us-east-1"  = "ami-0990e7074b32986af"
    "us-east-2"  = "ami-0e71db082192a9cf7"
    "eu-north-1" = "ami-006af066a79f5190f"
    "eu-west-1"  = "ami-06028a225ee106d6f"
  }

  region_ami_map_talos = {
    "us-east-1"  = "ami-064e388d915377924"
    "us-east-2"  = "ami-090fb8e21a10977b3"
    "eu-north-1" = "ami-07bd569b95443e16c"
    "eu-west-1"  = "ami-0c2f6db59bde696db"
  }
  
  region_ami_maps = {
    rhel9        = local.region_ami_map_rhel9
    rhel10        = local.region_ami_map_rhel10
    ubuntu2404  = local.region_ami_map_ubuntu24
    ubuntu2204  = local.region_ami_map_ubuntu22
  }

  region_ami_map = local.region_ami_maps[var.storage_nodes_distro]

  ami_map = {
    "amd64" = local.region_ami_map
    "arm64" = local.region_ami_map_rhel9_arm
  }

  sbcli_pkg = var.sbcli_pkg_version == "" ? var.sbcli_cmd : "${var.sbcli_cmd}==${var.sbcli_pkg_version}"

  az_suffix_to_number = {
    "a" = 0
    "b" = 1
    "c" = 2
    "d" = 3
  }

  az_suffix = substr(var.az, -1, 1)
  az_index  = lookup(local.az_suffix_to_number, local.az_suffix, -1)

  efs_file_systems = {
    mongodb_data    = "mongodb_data"
    os_data         = "os_data"
    graylog_data    = "graylog_data"
    graylog_journal = "graylog_journal"
    graylog_config  = "graylog_config"
    grafana_data    = "grafana_data"
    prometheus_data = "prometheus_data"
  }

  account_id = data.aws_caller_identity.current.account_id
}
