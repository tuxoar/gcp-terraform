# -----------------------------------------------------------------------------
# Shared VPC: host project owns the network; service projects attach.
#
# Layout:
#   prod-vpc (custom mode)
#     └── subnet gke-nodes  10.10.0.0/22  (us-central1)
#           ├── secondary "pods"     10.20.0.0/16
#           └── secondary "services" 10.30.0.0/20
#   Cloud Router + Cloud NAT          (egress for private nodes)
#   Firewall: allow IAP→SSH on bastion SA tag
#   Firewall: allow intra-subnet
# -----------------------------------------------------------------------------

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
}

resource "google_compute_shared_vpc_service_project" "service" {
  host_project    = var.host_project_id
  service_project = var.service_project_id
  depends_on      = [google_compute_shared_vpc_host_project.host]
}

resource "google_compute_network" "prod" {
  project                 = var.host_project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke_nodes" {
  project                  = var.host_project_id
  name                     = var.subnet_name
  region                   = var.region
  network                  = google_compute_network.prod.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# -----------------------------------------------------------------------------
# Cloud NAT — egress for private nodes (no public IPs).
# -----------------------------------------------------------------------------
resource "google_compute_router" "nat" {
  project = var.host_project_id
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.prod.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.host_project_id
  name                               = "nat-config"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# -----------------------------------------------------------------------------
# Firewall rules
#
# We prefer service-account-based targets to network tags. SAs require
# iam.serviceAccountUser to attach; tags can be set by anyone with
# compute.instances.setTags. (Tag-based rules are still common — know both.)
# -----------------------------------------------------------------------------

# Intra-subnet traffic — pods and nodes need to talk to each other.
resource "google_compute_firewall" "allow_internal" {
  project = var.host_project_id
  name    = "allow-internal"
  network = google_compute_network.prod.name

  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

# IAP TCP forwarding source range for SSH to the bastion. The actual bastion
# instance lives in the service project and uses the same VPC via Shared VPC.
resource "google_compute_firewall" "allow_iap_ssh" {
  project = var.host_project_id
  name    = "allow-iap-ssh"
  network = google_compute_network.prod.name

  direction = "INGRESS"
  priority  = 1000

  # 35.235.240.0/20 is the IAP TCP forwarding range — Google publishes this.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Explicit egress-deny default? GCP's implied egress is "allow all," ingress is
# "deny all." We leave egress default (allow) so Cloud NAT works without
# extra rules. For prod, add an egress deny + explicit allows.

# -----------------------------------------------------------------------------
# Shared VPC IAM grants required for GKE in a service project.
#
# - container.hostServiceAgentUser:  the service project's GKE service agent
#   needs to act as the host service agent.
# - compute.networkUser:             the service project's GKE service agent
#   AND the K8s cluster service account need use of the specific subnet and
#   its secondary ranges.
# -----------------------------------------------------------------------------

locals {
  service_gke_agent      = "serviceAccount:service-${var.service_project_number}@container-engine-robot.iam.gserviceaccount.com"
  service_cloud_services = "serviceAccount:${var.service_project_number}@cloudservices.gserviceaccount.com"
}

resource "google_project_iam_member" "gke_host_service_agent" {
  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = local.service_gke_agent
}

resource "google_compute_subnetwork_iam_member" "gke_subnet_user" {
  for_each = toset([local.service_gke_agent, local.service_cloud_services])

  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.gke_nodes.name
  role       = "roles/compute.networkUser"
  member     = each.value
}
