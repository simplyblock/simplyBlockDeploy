variable "region" {
  default     = "us-east-2"
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
  default     = "us-east-2b"
}

variable "env" {
  default = "dev"
  type    = string
}

variable "sbcli_cmd" {
  default     = "sbcli-pre"
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
  default = 0
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
  default = "i3en.2xlarge" # Simplyblock requires atleast 6 VPCs per storage node
  type    = string
}

variable "nr_hugepages" {
  default     = 2048
  description = "number of huge pages. To be used when eks is not enabled"
  type        = number
}

variable "storage_nodes_arch" {
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["arm64", "amd64"], var.storage_nodes_arch)
    error_message = "The architecture type must be either 'arm64' or 'amd64'."
  }
}

variable "ssh_key_path" {
  description = "Path to the public SSH key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "max_lvol" {
  type        = number
  default     = 20
}

variable "max_size" {
  type        = string
  default     = "200G"
}

variable "nodes_per_socket" {
  type        = number
  default     = 1
}

variable "socket_to_use" {
  type        = string
  default     = "0"
}

variable "pci_allowed" {
  type        = list(string)
  default     = [""]
}

variable "pci_blocked" {
  type        = list(string)
  default     = [""]
}
