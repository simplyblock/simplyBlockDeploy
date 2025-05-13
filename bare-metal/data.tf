data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_secretsmanager_secret_version" "simply" {
  secret_id = local.selected_key_name
}
