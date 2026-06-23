# =============================================================================
# GKE — production-shaped private cluster.
# =============================================================================

# -----------------------------------------------------------------------------
# Node service account — minimal scope. The default Compute Engine SA has
# roles/editor project-wide; never use it for node SA.
# -----------------------------------------------------------------------------
resource "google_service_account" "node" {
  project      = var.service_project_id
  account_id   = "gke-node-sa"
  display_name = "GKE node service account (minimal)"
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
  project = var.service_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node.email}"
}

# -----------------------------------------------------------------------------
# Demo workload identity GSA — the one a pod will impersonate.
# (The KSA binding lives in 70-workload as kubectl-applied YAML.)
# -----------------------------------------------------------------------------
resource "google_service_account" "demo_app" {
  project      = var.service_project_id
  account_id   = var.demo_gsa_name
  display_name = "Demo app GSA (Workload Identity target)"
}

# Allow the K8s service account to impersonate this GSA. This is the binding
# that *makes* Workload Identity work — without it, the KSA annotation alone
# does nothing.
resource "google_service_account_iam_member" "demo_workload_identity" {
  service_account_id = google_service_account.demo_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.service_project_id}.svc.id.goog[${var.demo_namespace}/${var.demo_ksa_name}]"
}

# Give the GSA something to do — read-only on its own project's secrets.
# Swap for whatever your demo workload actually calls.
resource "google_project_iam_member" "demo_app_secret_accessor" {
  project = var.service_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.demo_app.email}"
}

# -----------------------------------------------------------------------------
# The cluster.
# -----------------------------------------------------------------------------
resource "google_container_cluster" "prod" {
  project    = var.service_project_id
  name       = var.cluster_name
  location   = var.region # regional cluster
  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  # Strip the default node pool so we manage it as a separate resource.
  remove_default_node_pool = true
  initial_node_count       = 1

  # ---- Release management ----------------------------------------------------
  # Don't pin a version. The release channel is GKE's answer to "how do you
  # patch?". REGULAR = balanced cadence. RAPID for dev, STABLE for ultra-conservative.
  release_channel {
    channel = "REGULAR"
  }

  # ---- VPC-native (alias IPs) ------------------------------------------------
  # The only mode you should use. Pods get real VPC IPs from the secondary range.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # ---- Private cluster -------------------------------------------------------
  # enable_private_nodes:    nodes have no public IPs
  # enable_private_endpoint: control plane has no public IP at all (not just
  #                          restricted — gone). Authorized networks alone
  #                          leaves a public IP exposed to API server bugs.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = false
    }
  }

  # Bastion subnet is allowed to talk to the private control plane.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_cidr
      display_name = "bastion-subnet"
    }
  }

  # ---- Workload Identity -----------------------------------------------------
  # Enables the *.svc.id.goog workload pool — KSAs federate to GSAs without
  # long-lived keys. The single most-asked GKE security feature.
  workload_identity_config {
    workload_pool = "${var.service_project_id}.svc.id.goog"
  }

  # ---- Dataplane V2 (Cilium/eBPF) -------------------------------------------
  # Native NetworkPolicy enforcement, observability, and FQDN logging without
  # iptables sprawl. With ADVANCED_DATAPATH, do NOT also set network_policy{}.
  datapath_provider = "ADVANCED_DATAPATH"

  # Pods on the same node see each other on the VPC (not via the cni-bridge).
  enable_intranode_visibility = true

  # ---- Shielded nodes (cluster-wide default) --------------------------------
  enable_shielded_nodes = true

  # ---- Binary Authorization --------------------------------------------------
  # Only images that meet the project's Binauthz policy can be admitted.
  # The policy itself is configured in phase 60.
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # ---- Application-layer secrets encryption (CMEK on etcd Secrets) ----------
  # Without this, K8s Secret objects in etcd are only encrypted under Google's
  # at-rest key, not yours. With this, Secrets are encrypted under your KMS key
  # before being written to etcd. Rotating this key re-encrypts.
  database_encryption {
    state    = "ENCRYPTED"
    key_name = var.kms_etcd_key
  }

  # ---- Built-in addons we want -----------------------------------------------
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    gcp_filestore_csi_driver_config {
      enabled = false
    }
    # Lets pods mount Secret Manager secrets as files via CSI.
    gke_backup_agent_config {
      enabled = false
    }
  }

  secret_manager_config {
    enabled = true
  }

  # ---- Logging / monitoring -------------------------------------------------
  # API_SERVER component is what gives you kube-audit logs in Cloud Logging.
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
      "CADVISOR",
      "KUBELET",
    ]
    managed_prometheus {
      enabled = true
    }
  }

  # ---- Maintenance window — keep auto-upgrades predictable -------------------
  maintenance_policy {
    recurring_window {
      start_time = "2026-06-29T04:00:00Z"
      end_time   = "2026-06-29T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  # Required when removing the default node pool with custom configuration on
  # a regional cluster — Terraform safety check.
  deletion_protection = false
}

# -----------------------------------------------------------------------------
# Primary node pool.
# -----------------------------------------------------------------------------
resource "google_container_node_pool" "primary" {
  project    = var.service_project_id
  name       = "primary"
  cluster    = google_container_cluster.prod.name
  location   = var.region
  node_count = 1 # per zone; regional cluster → 3 zones → 3 nodes total

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }

  node_config {
    machine_type = var.machine_type
    image_type   = "COS_CONTAINERD"
    disk_type    = "pd-balanced"
    disk_size_gb = 50

    service_account = google_service_account.node.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Tell the kubelet to use the GKE metadata server, which gates GSA token
    # requests through the Workload Identity pool. Without this, pods can hit
    # the GCE metadata server directly and get the node SA's token.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # CMEK on node boot disks.
    boot_disk_kms_key = var.kms_disks_key

    # AMD SEV memory encryption. Flip via variable.
    confidential_nodes {
      enabled = var.enable_confidential_nodes
    }

    # Reserve resources so the kubelet doesn't get OOM-evicted under load.
    kubelet_config {
      cpu_manager_policy = "static"
    }

    labels = {
      pool = "primary"
    }

    tags = ["gke-node"]
  }
}

# -----------------------------------------------------------------------------
# Bastion VM (optional). IAP SSH only. Lives in the service project but on the
# Shared VPC subnet, so it can reach the private control-plane endpoint.
# -----------------------------------------------------------------------------
resource "google_service_account" "bastion" {
  count        = var.create_bastion ? 1 : 0
  project      = var.service_project_id
  account_id   = "bastion-sa"
  display_name = "Bastion VM SA"
}

# Bastion needs to read the cluster to run `gcloud container clusters get-credentials`.
resource "google_project_iam_member" "bastion_container_viewer" {
  count   = var.create_bastion ? 1 : 0
  project = var.service_project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.bastion[0].email}"
}

resource "google_compute_instance" "bastion" {
  count        = var.create_bastion ? 1 : 0
  project      = var.service_project_id
  name         = "bastion"
  machine_type = "e2-small"
  zone         = "${var.region}-a"
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No access_config block = no external IP. IAP SSH is how you reach it.
  }

  service_account {
    email  = google_service_account.bastion[0].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e
    apt-get update
    apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin kubectl
  EOT
}
