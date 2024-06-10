variable "region" {
  default = "us-west-2"
}

variable "mgmt_node_instance_ids" {
    type = list(string)
}

variable "api_gateway_id" {
    type = string
}

variable "loadbalancer_id" {
    type = string
}

variable "public_subnets" {
    type = list(string)
}
variable "vpc_id" {
    type = string
}
