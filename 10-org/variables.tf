variable "org_id" {
  description = "Numeric org ID (gcloud organizations list)."
  type        = string
}

variable "customer_id" {
  description = <<EOT
Cloud Identity customer ID, e.g. C0abc1234. Required for the
iam.allowedPolicyMemberDomains org policy. Fetch with:
  gcloud organizations describe ORG_ID --format='value(directoryCustomerId)'
EOT
  type        = string
}

variable "parent_folder_id" {
  description = "Optional parent folder (e.g. folders/12345). Empty = lab folder lives at org root."
  type        = string
  default     = ""
}

variable "lab_name" {
  description = "Display name for the top-level lab folder."
  type        = string
  default     = "lab"
}

variable "enforce_disable_sa_keys" {
  description = "Disable creation of service account keys org-wide on the lab folder."
  type        = bool
  default     = true
}

variable "enforce_domain_restriction" {
  description = "Restrict IAM grants to principals from your Cloud Identity customer."
  type        = bool
  default     = true
}

variable "enforce_require_oslogin" {
  description = "Require OS Login for SSH (no project SSH metadata keys)."
  type        = bool
  default     = true
}

variable "enforce_deny_external_ips" {
  description = "Deny external IPs on Compute Engine instances by default."
  type        = bool
  default     = true
}

variable "enforce_uniform_bucket_access" {
  description = "Force GCS uniform bucket-level access (no ACLs)."
  type        = bool
  default     = true
}
