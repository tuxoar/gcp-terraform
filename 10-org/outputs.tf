output "lab_folder_id" {
  description = "Full resource name of the lab folder, e.g. folders/12345."
  value       = google_folder.lab.name
}

output "shared_folder_id" {
  value = google_folder.shared.name
}

output "workloads_folder_id" {
  value = google_folder.workloads.name
}
