variable "org_id" {
  description = "Numeric org ID. The bootstrap project lives directly under the org (not under the lab folder, so phase 10 can be destroyed without nuking state)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID."
  type        = string
}

variable "parent_folder_id" {
  description = "Optional folder for the bootstrap project (e.g. a pre-existing shared/admin folder). Empty = org root."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region for the state bucket and its KMS key."
  type        = string
  default     = "us-central1"
}

variable "project_prefix" {
  type    = string
  default = "tf-state"
}

variable "bucket_prefix" {
  description = "GCS bucket names are globally unique — a random suffix gets appended."
  type        = string
  default     = "tf-state"
}

variable "additional_state_admins" {
  description = "Extra principals (user:foo@bar / group:eng@bar / serviceAccount:…) that get roles/storage.objectAdmin on the state bucket."
  type        = list(string)
  default     = []
}
