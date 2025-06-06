data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_secretsmanager_secret_version" "simply" {
  secret_id = local.selected_key_name
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
