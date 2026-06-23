output "host_project_id" {
  value = google_project.host.project_id
}

output "host_project_number" {
  value = google_project.host.number
}

output "service_project_id" {
  value = google_project.service.project_id
}

output "service_project_number" {
  value = google_project.service.number
}
