variable "host_project_id" {
  type = string
}

variable "service_project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "prod"
}

variable "network_self_link" {
  type = string
}

variable "subnet_self_link" {
  type = string
}

variable "subnet_cidr" {
  description = "CIDR of the GKE node subnet — used as the master_authorized_networks entry so the bastion can reach the private endpoint."
  type        = string
}

variable "pods_range_name" {
  type    = string
  default = "pods"
}

variable "services_range_name" {
  type    = string
  default = "services"
}

variable "master_ipv4_cidr_block" {
  description = "Private /28 used by the control plane endpoint. Must not overlap with the VPC."
  type        = string
  default     = "172.16.0.0/28"
}

variable "kms_etcd_key" {
  description = "Full resource ID of the KMS key for application-layer secrets encryption."
  type        = string
}

variable "kms_disks_key" {
  description = "Full resource ID of the KMS key for node boot disks."
  type        = string
}

variable "enable_confidential_nodes" {
  description = "Enable Confidential GKE Nodes (AMD SEV). Forces n2d/c2d/c3d machine types."
  type        = bool
  default     = false
}

variable "machine_type" {
  type    = string
  default = "n2d-standard-2"
}

variable "create_bastion" {
  description = "Create a bastion VM in the service project (reachable via IAP) for kubectl access to the private endpoint."
  type        = bool
  default     = true
}

variable "demo_gsa_name" {
  description = "Google service account that the demo workload will impersonate via Workload Identity."
  type        = string
  default     = "app-gsa"
}

variable "demo_namespace" {
  type    = string
  default = "app"
}

variable "demo_ksa_name" {
  type    = string
  default = "app-ksa"
}
