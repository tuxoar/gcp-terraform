variable "billing_account" {
  description = "Billing account ID (e.g. 0XAAAA-1BBBBB-2CCCCC)."
  type        = string
}

variable "lab_folder_id" {
  description = "Output from 10-org. e.g. folders/123."
  type        = string
}

variable "host_project_prefix" {
  type    = string
  default = "net-host"
}

variable "service_project_prefix" {
  type    = string
  default = "gke-prod"
}

variable "region" {
  type    = string
  default = "us-central1"
}
