locals {
  volume_device_names = ["/dev/sdi", "/dev/sdj", "/dev/sdk", "/dev/sdl", "/dev/sdm", "/dev/sdn"]

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
    "us-east-1"  = "ami-023c11a32b0207432"
    "us-east-2"  = "ami-0ef50c2b2eb330511"
    "eu-north-1" = "ami-01d565a5f2da42e6f"
    "eu-west-1"  = "ami-049b0abf844cab8d7"
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
}
