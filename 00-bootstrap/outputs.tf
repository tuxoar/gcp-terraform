output "bootstrap_project_id" {
  value = google_project.tf_state.project_id
}

output "bucket_name" {
  description = "Paste this into each phase's versions.tf backend block."
  value       = google_storage_bucket.tf_state.name
}

output "kms_key" {
  value = google_kms_crypto_key.state.id
}

output "backend_block" {
  description = "Drop-in backend stanza. Replace <prefix> with 10-org, 20-projects, etc."
  value       = <<EOT
terraform {
  backend "gcs" {
    bucket = "${google_storage_bucket.tf_state.name}"
    prefix = "<prefix>"
  }
}
EOT
}

output "next_steps" {
  value = <<EOT
Bucket created: gs://${google_storage_bucket.tf_state.name}

To put each phase's state in the bucket:
  1. Edit <phase>/versions.tf — uncomment the backend "gcs" stanza and set:
        bucket = "${google_storage_bucket.tf_state.name}"
        prefix = "<phase>"          # e.g. "10-org"
  2. In <phase>/ run: terraform init -migrate-state
     (Says "yes" when it asks to copy local state to the bucket.)

To also migrate THIS bootstrap module's state into the bucket it created,
edit 00-bootstrap/versions.tf and uncomment the backend block, then
  terraform init -migrate-state
EOT
}
