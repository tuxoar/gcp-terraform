output "cluster_name" {
  value = google_container_cluster.prod.name
}

output "cluster_location" {
  value = google_container_cluster.prod.location
}

output "cluster_endpoint" {
  value     = google_container_cluster.prod.endpoint
  sensitive = true
}

output "node_sa_email" {
  value = google_service_account.node.email
}

output "demo_gsa_email" {
  value       = google_service_account.demo_app.email
  description = "Annotate the KSA with: iam.gke.io/gcp-service-account=<this>"
}

output "bastion_name" {
  value = try(google_compute_instance.bastion[0].name, null)
}

output "kubectl_setup" {
  value = <<EOT
# From the bastion (or a workstation in the VPC):
gcloud compute ssh ${try(google_compute_instance.bastion[0].name, "bastion")} \
  --tunnel-through-iap --project=${var.service_project_id} --zone=${var.region}-a

# Then on the bastion:
gcloud container clusters get-credentials ${google_container_cluster.prod.name} \
  --region=${var.region} --project=${var.service_project_id}

# Apply the demo workload:
kubectl apply -f 70-workload/
EOT
}
