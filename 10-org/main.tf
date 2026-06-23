# -----------------------------------------------------------------------------
# Folder hierarchy
#
# Org → (optional) parent folder → lab
#                                   ├── shared       (networking host project lives here)
#                                   └── workloads    (service projects live here)
# -----------------------------------------------------------------------------

locals {
  parent = var.parent_folder_id != "" ? var.parent_folder_id : "organizations/${var.org_id}"
}

resource "google_folder" "lab" {
  display_name = var.lab_name
  parent       = local.parent
}

resource "google_folder" "shared" {
  display_name = "shared"
  parent       = google_folder.lab.name
}

resource "google_folder" "workloads" {
  display_name = "workloads"
  parent       = google_folder.lab.name
}

# -----------------------------------------------------------------------------
# Org policies (v2). All scoped to the lab folder so they don't disrupt other
# work in your org. Real prod usually sets these at the org root.
# -----------------------------------------------------------------------------

# Disable creation of service account keys. The #1 GCP credential-leak vector.
resource "google_org_policy_policy" "disable_sa_keys" {
  count  = var.enforce_disable_sa_keys ? 1 : 0
  name   = "${google_folder.lab.name}/policies/iam.disableServiceAccountKeyCreation"
  parent = google_folder.lab.name

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Only principals from your Cloud Identity customer can be granted IAM. Stops
# anyone from accidentally granting allUsers/allAuthenticatedUsers.
resource "google_org_policy_policy" "domain_restriction" {
  count  = var.enforce_domain_restriction ? 1 : 0
  name   = "${google_folder.lab.name}/policies/iam.allowedPolicyMemberDomains"
  parent = google_folder.lab.name

  spec {
    rules {
      values {
        allowed_values = ["C${replace(var.customer_id, "C", "")}"]
      }
    }
  }
}

# SSH via IAM (OS Login), not project metadata SSH keys.
resource "google_org_policy_policy" "require_oslogin" {
  count  = var.enforce_require_oslogin ? 1 : 0
  name   = "${google_folder.lab.name}/policies/compute.requireOsLogin"
  parent = google_folder.lab.name

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Deny external IPs by default. Specific instances can be allow-listed by
# overriding this policy at the project level later if needed.
resource "google_org_policy_policy" "deny_external_ips" {
  count  = var.enforce_deny_external_ips ? 1 : 0
  name   = "${google_folder.lab.name}/policies/compute.vmExternalIpAccess"
  parent = google_folder.lab.name

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

# Force GCS uniform bucket-level access (kills ACL-based access).
resource "google_org_policy_policy" "uniform_bucket_access" {
  count  = var.enforce_uniform_bucket_access ? 1 : 0
  name   = "${google_folder.lab.name}/policies/storage.uniformBucketLevelAccess"
  parent = google_folder.lab.name

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
