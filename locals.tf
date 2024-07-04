data "aws_caller_identity" "current" {}

locals {
  volume_device_names = ["/dev/sdi", "/dev/sdj", "/dev/sdk", "/dev/sdl", "/dev/sdm", "/dev/sdn", "/dev/sdo"]

  snodes = toset([for n in range(var.storage_nodes) : tostring(n)])

  node_disks = { for pair in setproduct(local.snodes, slice(local.volume_device_names, 0, var.volumes_per_storage_nodes)) : "${pair[0]}:${pair[1]}" => {
    node_name     = pair[0]
    disk_dev_path = pair[1]
  } }

  key_name = {
    "us-east-1"  = "simplyblock-us-east-1.pem"
    "us-east-2"  = "simplyblock-us-east-2.pem"
    "eu-north-1" = "simplyblock-eu-north-1.pem"
    "eu-west-1"  = "simplyblock-eu-west-1.pem"
  }

  selected_key_name = try(local.key_name[var.region], "simplyblock-us-east-2.pem")

  region_ami_map = {
    "us-east-1"  = "ami-0d647905a963bb139"
    "us-east-2"  = "ami-00ff94d69b3ced2aa"
    "eu-north-1" = "ami-0f8c92340db698d74"
    "eu-west-1"  = "ami-02a1fc058c85a41dd"
  }

  region_ami_map_arm = {
    "us-east-1"  = "ami-07472131ec292b5da"
    "us-east-2"  = "ami-08f9f3bb075432791"
    "eu-north-1" = "ami-096f8d910bbf871bc"
    "eu-west-1"  = "ami-02b8573b23fde21aa"
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
