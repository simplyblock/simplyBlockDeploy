variable "region" {
  default     = "eu-central-1"
  description = "region to provision"
  type        = string
  validation {
    condition     = can(regex("^us-east-1$|^us-east-2$|^us-west-1$|^us-west-2$|^eu-west-1$|^eu-west-2$|^eu-central-1$|^eu-north-1$", var.region))
    error_message = "Invalid AWS region. Please choose one of: us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1, eu-west-2, eu-central-1, eu-north-1."
  }
}

variable "az" {
  description = "availability zone to provision"
  type        = string
  default     = "eu-central-1a"
}

variable "env" {
  default = "staging"
  type    = string
}

variable "sbcli_cmd" {
  default     = "sbcli-dev"
  description = "sbcli command to be used"
  type        = string
}

variable "sbcli_pkg_version" {
  default     = ""
  description = "sbcli package and version to be used. ex: 2.0.0"
  type        = string
}

variable "cluster_name" {
  default     = "eks"
  description = "EKS Cluster name"
}

variable "whitelist_ips" {
  type    = list(string)
  default = ["0.0.0.0/0"]
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

variable "enable_apigateway" {
  default = 1
  type    = number
}

variable "tf_state_bucket_name" {
  default = "simplyblock-terraform-state-bucket"
  type    = string
}

variable "extra_nodes_arch" {
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["arm64", "amd64"], var.extra_nodes_arch)
    error_message = "The architecture type must be either 'arm64' or 'amd64'."
  }
}

variable "storage_nodes_arch" {
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["arm64", "amd64"], var.storage_nodes_arch)
    error_message = "The architecture type must be either 'arm64' or 'amd64'."
  }
}

variable "snode_deploy_on_k8s" {
  type        = string
  default     = "false"

  validation {
    condition     = contains(["false", "true"], var.snode_deploy_on_k8s)
    error_message = "The value must be either 'true' or 'false'."
  }
}
