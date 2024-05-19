variable "region" {
  default = "us-west-2"
}

variable "mgmt_node_private_ip" {
    type = string
}

variable "mgmt_node_instance_id" {
    type = string
}

variable "api_gateway_id" {
    type = string
}

variable "public_subnets" {
    type = list(string)
}
