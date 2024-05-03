variable "region" {
  default     = "us-east-2"
  description = "region to provision"
  type        = string
  validation {
    condition     = can(regex("^us-east-1$|^us-east-2$|^us-west-1$|^us-west-2$|^eu-west-1$|^eu-west-2$|^eu-central-1$|^eu-north-1$", var.region))
    error_message = "Invalid AWS region. Please choose one of: us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1, eu-west-2, eu-central-1, eu-north-1."
  }
}

variable "sbcli_pkg" {
  default     = "sbcli-dev"
  description = "sbcli package to be used"
  type        = string
  validation {
    condition     = can(regex("^sbcli-dev$|^sbcli-release$", var.sbcli_pkg))
    error_message = "Invalid sbcli package. Please choose one of: sbcli-dev, sbcli-release."
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
  default = "m5.large"
  type    = string
}

variable "storage_nodes_ebs_size1" {
  default = 2
  type    = number
}

variable "storage_nodes_ebs_size2" {
  default = 50
  type    = number
}

variable "volumes_per_storage_nodes" {
  default = 1
  type    = number
  validation {
    condition     = var.volumes_per_storage_nodes <= 6
    error_message = "The number of volumes per storage node must not exceed 6."
  }
}

variable "nr_hugepages" {
  default     = 2048
  description = "number of huge pages"
  type        = number
}

output "storage_public_ips" {
  value = join(" ", [for inst in aws_instance.storage_nodes : inst.public_ip])
}
