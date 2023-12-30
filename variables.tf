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
