terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bootstrap state is intentionally LOCAL on first apply — there's no bucket
  # yet to put it in (chicken-and-egg). After the bucket exists, you can
  # migrate this state into it too:
  #
  #   1. Uncomment the backend block below
  #   2. Replace <bucket> with the `bucket_name` output from this module
  #   3. `terraform init -migrate-state`
  #
  # backend "gcs" {
  #   bucket = "<bucket>"
  #   prefix = "00-bootstrap"
  # }
}

provider "google" {}
