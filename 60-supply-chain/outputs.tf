output "ar_repo_url" {
  value = "${var.region}-docker.pkg.dev/${var.service_project_id}/${var.ar_repo_name}"
}

output "attestor_name" {
  value = google_binary_authorization_attestor.built_by_ci.name
}

output "ci_signer_key_version" {
  value = data.google_kms_crypto_key_version.ci_signer.id
}

output "sign_command_template" {
  value = <<EOT
# After building & pushing an image, capture the digest and sign:
DIGEST="$(gcloud artifacts docker images describe \
  ${var.region}-docker.pkg.dev/${var.service_project_id}/${var.ar_repo_name}/<image>:<tag> \
  --format='value(image_summary.digest)')"

gcloud beta container binauthz attestations sign-and-create \
  --artifact-url="${var.region}-docker.pkg.dev/${var.service_project_id}/${var.ar_repo_name}/<image>@$DIGEST" \
  --attestor=${google_binary_authorization_attestor.built_by_ci.name} \
  --attestor-project=${var.service_project_id} \
  --keyversion-project=${var.service_project_id} \
  --keyversion-location=${var.region} \
  --keyversion-keyring=binauthz \
  --keyversion-key=ci-signer \
  --keyversion=1
EOT
}
