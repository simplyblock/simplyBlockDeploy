variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "talos_version" {
  description = "Talos release tag to use for AMI lookup (e.g. v1.11.0)"
  type        = string
  default     = "v1.11.0"
}

variable "cluster_name" {
  type    = string
  default = "talos-tf-cluster"
}

variable "control_plane_instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_desired_capacity" {
  type    = number
  default = 2
}

variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "storage_node_sg" {
  type = string
}
