variable "region" {
  default = "us-west-2"
}

variable "mgmt_node_private_ips" {
    type = list(string)
}

variable "mgmt_node_instance_ids" {
    type = list(string)
}

variable "api_gateway_id" {
    type = string
}

variable "public_subnets" {
    type = list(string)
}
variable "vpc_id" {
    type = string
}
