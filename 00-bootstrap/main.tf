# =============================================================================
# Pre-lab: Terraform state backend on GCS.
#
# Creates a dedicated "tf-state" project, a regional KMS key for CMEK, and a
# GCS bucket configured for production Terraform use:
#   - Object versioning (rollback)
#   - Uniform bucket-level access (no ACLs)
#   - Public access prevention (defense in depth even if IAM is misconfigured)
#   - CMEK encryption with a rotating KMS key
#   - Lifecycle: keep last 10 versions, delete archived versions after 90 days
#
# Why a dedicated project for state? So you can destroy the lab folder
# (phase 10) without taking out your state bucket. The bootstrap project
# sits parallel to — not under — the lab folder.
#
# GCS as a Terraform backend gives you:
#   - State locking (atomic generation conditions on the state object)
#   - Server-side encryption + your CMEK
#   - Versioning, so a corrupted state file is recoverable
#   - Shareable with teammates without copying *.tfstate around
# =============================================================================

locals {
  parent = var.parent_folder_id != "" ? var.parent_folder_id : "organizations/${var.org_id}"
}

resource "random_id" "suffix" {
  byte_length = 3
}

# -----------------------------------------------------------------------------
# Dedicated bootstrap project.
# -----------------------------------------------------------------------------
resource "google_project" "tf_state" {
  name            = var.project_prefix
  project_id      = "${var.project_prefix}-${random_id.suffix.hex}"
  billing_account = var.billing_account

  # Parent set via folder_id OR org_id depending on caller input.
  folder_id = var.parent_folder_id != "" ? trimprefix(var.parent_folder_id, "folders/") : null
  org_id    = var.parent_folder_id == "" ? var.org_id : null

  deletion_policy = "DELETE"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project                    = google_project.tf_state.project_id
  service                    = each.key
  disable_dependent_services = true
}

# -----------------------------------------------------------------------------
# KMS keyring + key for the state bucket.
# -----------------------------------------------------------------------------
resource "google_kms_key_ring" "state" {
  project    = google_project.tf_state.project_id
  name       = "tf-state"
  location   = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "state" {
  name            = "state"
  key_ring        = google_kms_key_ring.state.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = false # set true in real prod — destroying this orphans state
  }
}

# GCS service agent must be allowed to use the KMS key to encrypt/decrypt
# bucket objects. This data source materializes the agent.
data "google_storage_project_service_account" "gcs" {
  project    = google_project.tf_state.project_id
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key_iam_member" "gcs_encrypt_decrypt" {
  crypto_key_id = google_kms_crypto_key.state.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

# -----------------------------------------------------------------------------
# State bucket.
# -----------------------------------------------------------------------------
resource "google_storage_bucket" "tf_state" {
  project  = google_project.tf_state.project_id
  name     = "${var.bucket_prefix}-${random_id.suffix.hex}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.state.id
  }

  # Keep the last 10 noncurrent versions per object.
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Hard-delete archived versions older than 90d. Plenty of time to recover.
  lifecycle_rule {
    condition {
      age        = 90
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Set true ONLY for lab use. In prod, force_destroy = false stops `terraform
  # destroy` from wiping the bucket out from under you.
  force_destroy = true

  depends_on = [google_kms_crypto_key_iam_member.gcs_encrypt_decrypt]
}

# -----------------------------------------------------------------------------
# Optional extra admins on the state bucket.
# -----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "extra_admins" {
  for_each = toset(var.additional_state_admins)
  bucket   = google_storage_bucket.tf_state.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}
