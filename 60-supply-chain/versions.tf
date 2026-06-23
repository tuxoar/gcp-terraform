terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # After applying 00-bootstrap, paste its `bucket_name` output below and run
  # `terraform init -migrate-state` to move local state into GCS.
  # backend "gcs" {
  #   bucket = "<tf-state-bucket-from-00-bootstrap>"
  #   prefix = "60-supply-chain"
  # }
}

provider "google" {}
