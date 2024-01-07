variable "cluster_name" {
  default     = "simplyblock-eks-cluster"
  description = "EKS Cluster name"
}

variable "cluster_type" {
  default = "single"
  description = "the type of the cluster"

  validation {
    condition     = contains(["single", "ha"], var.cluster_type)
    error_message = "Valid values for cluster_type are (single, ha)."
  }
}

# todo: validate: if the cluster type is HA, there should be atleast 3 nodes

variable "enable_eks" {
  default = 0
  type = number
}

variable "storage_nodes" {
  default = 5
  type  = number
}

variable "mgmt_nodes" {
  default = 3
  type  = number
}

variable "cache_nodes" {
  default = 0
  type  = number
}
