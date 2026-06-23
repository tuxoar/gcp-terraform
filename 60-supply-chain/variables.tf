variable "service_project_id" {
  type = string
}

variable "service_project_number" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "kms_ar_key" {
  description = "KMS key for CMEK on the Artifact Registry repo."
  type        = string
}

variable "ar_repo_name" {
  type    = string
  default = "apps"
}

variable "attestor_name" {
  type    = string
  default = "built-by-ci"
}
