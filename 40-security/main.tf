# -----------------------------------------------------------------------------
# KMS keys + service-agent grants
#
# Three keys, all in the same region as the cluster:
#   - etcd   → application-layer secrets encryption for K8s Secrets in etcd
#   - disks  → CMEK on GKE node boot disks
#   - ar     → CMEK on Artifact Registry repos (used by phase 60)
#
# Service agents that need cryptoKeyEncrypterDecrypter:
#   - etcd:  GKE service agent       service-<NUM>@container-engine-robot.iam.gserviceaccount.com
#   - disks: Compute service agent   service-<NUM>@compute-system.iam.gserviceaccount.com
#   - ar:    AR service agent        service-<NUM>@gcp-sa-artifactregistry.iam.gserviceaccount.com
#
# google_project_service_identity materializes the service agent SAs so we can
# grant to them without race conditions on first apply.
# -----------------------------------------------------------------------------

resource "google_project_service_identity" "gke" {
  provider = google-beta
  project  = var.service_project_id
  service  = "container.googleapis.com"
}

resource "google_project_service_identity" "ar" {
  provider = google-beta
  project  = var.service_project_id
  service  = "artifactregistry.googleapis.com"
}

locals {
  gke_agent     = "serviceAccount:service-${var.service_project_number}@container-engine-robot.iam.gserviceaccount.com"
  compute_agent = "serviceAccount:service-${var.service_project_number}@compute-system.iam.gserviceaccount.com"
  ar_agent      = "serviceAccount:service-${var.service_project_number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# Keyring + keys
# -----------------------------------------------------------------------------
resource "google_kms_key_ring" "gke" {
  project  = var.service_project_id
  name     = "gke"
  location = var.region
}

resource "google_kms_crypto_key" "etcd" {
  name     = "etcd"
  key_ring = google_kms_key_ring.gke.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = false # set true in real prod
  }
}

resource "google_kms_crypto_key" "disks" {
  name            = "disks"
  key_ring        = google_kms_key_ring.gke.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "ar" {
  name            = "ar"
  key_ring        = google_kms_key_ring.gke.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Grants
# -----------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "etcd_gke" {
  crypto_key_id = google_kms_crypto_key.etcd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = local.gke_agent
  depends_on    = [google_project_service_identity.gke]
}

resource "google_kms_crypto_key_iam_member" "disks_compute" {
  crypto_key_id = google_kms_crypto_key.disks.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = local.compute_agent
}

resource "google_kms_crypto_key_iam_member" "ar_ar" {
  crypto_key_id = google_kms_crypto_key.ar.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = local.ar_agent
  depends_on    = [google_project_service_identity.ar]
}
