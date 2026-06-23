variable "host_project_id" {
  type = string
}

variable "service_project_id" {
  type = string
}

variable "service_project_number" {
  description = "Numeric project number — needed to address GKE service agents in IAM bindings."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "network_name" {
  type    = string
  default = "prod-vpc"
}

variable "subnet_name" {
  type    = string
  default = "gke-nodes"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/22"
}

variable "pods_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.30.0.0/20"
}
