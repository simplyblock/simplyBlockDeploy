variable "region" {
  default     = "us-east-2"
  description = "region to provision"
  type        = string
  validation {
    condition     = can(regex("^us-east-1$|^us-east-2$|^us-west-1$|^us-west-2$|^eu-west-1$|^eu-west-2$|^eu-central-1$", var.region))
    error_message = "Invalid AWS region. Please choose one of: us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1, eu-west-2, eu-central-1."
  }
}

variable "namespace" {
  default     = "csi"
  description = "global naming"
}

variable "cluster_name" {
  default     = "simplyblock-eks-cluster"
  description = "EKS Cluster name"
}

variable "whitelist_ips" {
  type    = list(string)
  default = ["195.176.32.0/24", "84.254.107.0/24", "178.197.210.0/24", "84.254.107.94/32", "0.0.0.0/0"]
}

variable "enable_eks" {
  default = 0
  type    = number
}

variable "key_name" {
  default = "simplyblock-us-east-2.pem"
  type    = string
}

variable "mgmt_nodes" {
  default = 1
  type    = number
}

variable "storage_nodes" {
  default = 3
  type    = number
}

variable "extra_nodes" {
  default = 0
  type    = number
}

variable "mgmt_nodes_instance_type" {
  default = "m5.large"
  type    = string 
}

variable "storage_nodes_instance_type" {
  default = "m5.large"
  type    = string 
}

variable "extra_nodes_instance_type" {
  default = "m6id.large"
  type    = string
}

variable "storage_nodes_ebs_size" {
  default = 50
  type    = number
}

variable "region_ami_map" {
  type = map(string)
  default = {
    "us-east-1" = "ami-023c11a32b0207432"
    "us-east-2" = "ami-0ef50c2b2eb330511"
  }
}
