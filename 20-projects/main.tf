# -----------------------------------------------------------------------------
# Project layout:
#   shared/   ← net-host-<suffix>     (Shared VPC host)
#   workloads/← gke-prod-<suffix>     (Shared VPC service project, runs GKE)
#
# We derive the parent folder for each project from the lab_folder_id by
# looking up child folders by display name. This avoids the user having to
# paste three folder IDs from the previous phase.
# -----------------------------------------------------------------------------

data "google_folder" "lab" {
  folder = var.lab_folder_id
}

# Look up the children created in 10-org by display name. (TF can't read
# children directly; we use data.google_folder with an explicit search.)
data "google_active_folder" "shared" {
  display_name = "shared"
  parent       = data.google_folder.lab.name
}

data "google_active_folder" "workloads" {
  display_name = "workloads"
  parent       = data.google_folder.lab.name
}

resource "random_id" "suffix" {
  byte_length = 3
}

# -----------------------------------------------------------------------------
# Host project (owns the Shared VPC)
# -----------------------------------------------------------------------------
resource "google_project" "host" {
  name            = var.host_project_prefix
  project_id      = "${var.host_project_prefix}-${random_id.suffix.hex}"
  folder_id       = data.google_active_folder.shared.name
  billing_account = var.billing_account

  # Don't fail destroy on linked default service accounts that GCP creates.
  deletion_policy = "DELETE"
}

resource "google_project_service" "host_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "dns.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
  project                    = google_project.host.project_id
  service                    = each.key
  disable_dependent_services = true
}

# -----------------------------------------------------------------------------
# Service project (runs GKE + workloads)
# -----------------------------------------------------------------------------
resource "google_project" "service" {
  name            = var.service_project_prefix
  project_id      = "${var.service_project_prefix}-${random_id.suffix.hex}"
  folder_id       = data.google_active_folder.workloads.name
  billing_account = var.billing_account

  deletion_policy = "DELETE"
}

resource "google_project_service" "service_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "containerscanning.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  project                    = google_project.service.project_id
  service                    = each.key
  disable_dependent_services = true
}

# -----------------------------------------------------------------------------
# Shared VPC association
#
# Host project must be enabled as a Shared VPC host BEFORE service projects
# can attach. The 30-network module handles the host enable; here we just
# create the projects so that module can run. We DO NOT attach the service
# project here either — that's also in 30-network so the VPC exists first.
# -----------------------------------------------------------------------------
