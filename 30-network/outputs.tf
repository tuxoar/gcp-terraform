output "network_self_link" {
  value = google_compute_network.prod.self_link
}

output "subnet_self_link" {
  value = google_compute_subnetwork.gke_nodes.self_link
}

output "subnet_name" {
  value = google_compute_subnetwork.gke_nodes.name
}

output "pods_range_name" {
  value = "pods"
}

output "services_range_name" {
  value = "services"
}

output "subnet_cidr" {
  value = google_compute_subnetwork.gke_nodes.ip_cidr_range
}
