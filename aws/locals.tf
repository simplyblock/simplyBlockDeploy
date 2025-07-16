data "aws_caller_identity" "current" {}

locals {
  snodes = toset([for n in range(var.enable_eks == 1 ? 0 : var.storage_nodes) : tostring(n)])
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
  region_ami_map = {
    "us-east-1"  = "ami-0ff9547ee3e11637a"
    "us-east-2"  = "ami-00b0bb86a4287f38f"
    "eu-north-1" = "ami-01997ffb7707167a4"
    "eu-west-1"  = "ami-0a3bac9371ffc12f8"
  }

  region_ami_map_arm = {
    "us-east-1"  = "ami-0990e7074b32986af"
    "us-east-2"  = "ami-0e71db082192a9cf7"
    "eu-north-1" = "ami-006af066a79f5190f"
    "eu-west-1"  = "ami-06028a225ee106d6f"
  }

  ami_map = {
    "amd64" = local.region_ami_map
    "arm64" = local.region_ami_map_arm
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

  account_id = data.aws_caller_identity.current.account_id
  current_user_arn  = data.aws_caller_identity.current.arn
}
