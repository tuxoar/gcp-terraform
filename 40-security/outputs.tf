output "kms_etcd_key" {
  value = google_kms_crypto_key.etcd.id
}

output "kms_disks_key" {
  value = google_kms_crypto_key.disks.id
}

output "kms_ar_key" {
  value = google_kms_crypto_key.ar.id
}

output "kms_keyring" {
  value = google_kms_key_ring.gke.id
}
