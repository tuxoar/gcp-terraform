# =============================================================================
# Supply chain: Artifact Registry (CMEK) + Binary Authorization attestor + policy
# =============================================================================

# -----------------------------------------------------------------------------
# Artifact Registry — Docker repo with CMEK + immutable tags.
# Container Analysis auto-scans pushed images for OS vulns.
# -----------------------------------------------------------------------------
resource "google_artifact_registry_repository" "apps" {
  project       = var.service_project_id
  location      = var.region
  repository_id = var.ar_repo_name
  format        = "DOCKER"

  kms_key_name = var.kms_ar_key

  docker_config {
    immutable_tags = true
  }

  # Cleanup: keep last 10 per tag, delete untagged after 30 days.
  cleanup_policies {
    id     = "keep-recent-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s" # 30 days
    }
  }
}

# -----------------------------------------------------------------------------
# Binary Authorization
#
# Pieces:
#   1. KMS asymmetric signing key — CI signs the digest with this.
#   2. Container Analysis Note — the "kind of statement" we're attesting to.
#   3. Attestor — references the note and the public key.
#   4. Policy — admission rule for the project. defaultAdmissionRule = DENY,
#      cluster-specific rule = REQUIRE_ATTESTATION from this attestor.
#
# To demo: try `kubectl run nginx --image=nginx:latest` from the bastion → DENY.
# To sign in CI:
#   gcloud beta container binauthz attestations sign-and-create \
#     --artifact-url=<region>-docker.pkg.dev/<proj>/apps/<image>@sha256:<digest> \
#     --attestor=<attestor> --attestor-project=<proj> \
#     --keyversion-project=<proj> --keyversion-location=<region> \
#     --keyversion-keyring=binauthz --keyversion-key=ci-signer --keyversion=1
# -----------------------------------------------------------------------------

resource "google_kms_key_ring" "binauthz" {
  project  = var.service_project_id
  name     = "binauthz"
  location = var.region
}

resource "google_kms_crypto_key" "ci_signer" {
  name     = "ci-signer"
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "RSA_SIGN_PKCS1_4096_SHA512"
    protection_level = "SOFTWARE"
  }
}

data "google_kms_crypto_key_version" "ci_signer" {
  crypto_key = google_kms_crypto_key.ci_signer.id
}

resource "google_container_analysis_note" "built_by_ci" {
  project = var.service_project_id
  name    = "built-by-ci"

  attestation_authority {
    hint {
      human_readable_name = "Built by CI"
    }
  }
}

resource "google_binary_authorization_attestor" "built_by_ci" {
  project = var.service_project_id
  name    = var.attestor_name

  attestation_authority_note {
    note_reference = google_container_analysis_note.built_by_ci.name

    public_keys {
      id = data.google_kms_crypto_key_version.ci_signer.id

      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.ci_signer.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.ci_signer.public_key[0].algorithm
      }
    }
  }
}

# Project-level Binauthz policy. Default DENY, allow images bearing a valid
# attestation from our attestor. System paths (kube-system, GKE-managed) are
# allowed via the global exemption list so kube-system pods still admit.
resource "google_binary_authorization_policy" "project" {
  project = var.service_project_id

  global_policy_evaluation_mode = "ENABLE" # honors Google's system-image allowlist

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      google_binary_authorization_attestor.built_by_ci.name,
    ]
  }

  # Exempt images you can't sign in your own CI (mirrored 3rd-party, etc.).
  # Add patterns sparingly — each one is a hole in your supply chain.
  admission_whitelist_patterns {
    name_pattern = "${var.region}-docker.pkg.dev/${var.service_project_id}/${var.ar_repo_name}/system/*"
  }
}
