# ==============================================================================
# TERRAFORM CONFIGURATION: CLOUDERA TO GCP TARGET INFRASTRUCTURE
# ==============================================================================
# This blueprint provisions the target landing zones for a Cloudera migration.
# It implements enterprise-grade storage, data warehousing, and IAM roles.

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "The target Google Cloud Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The primary region for resource deployment"
}

variable "migration_name_prefix" {
  type        = string
  default     = "cloudera-migration"
  description = "Prefix applied to resource names for tracking and filtering"
}

# ------------------------------------------------------------------------------
# 1. STORAGE LAYER (HDFS Replacement via GCS)
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "migration_lakehouse" {
  name                        = "${var.project_id}-${var.migration_name_prefix}-lakehouse"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  # Hierarchical structures mimic HDFS directories natively
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90 # Transition cold raw staging data after 90 days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# ------------------------------------------------------------------------------
# 2. DATA WAREHOUSE LAYER (Hive/Impala Replacement via BigQuery)
# ------------------------------------------------------------------------------
resource "google_bigquery_dataset" "migration_dataset" {
  dataset_id                  = replace("${var.migration_name_prefix}_dataset", "-", "_")
  friendly_name               = "Cloudera Migrated Data"
  description                 = "Target warehouse holding schemas and tables converted from Hive Metastore"
  location                    = var.region
  delete_contents_on_destroy = false

  labels = {
    env       = "migration-target"
    source    = "cloudera"
    managed_by = "terraform"
  }
}

# ------------------------------------------------------------------------------
# 3. IDENTITY & ACCESS MANAGEMENT (IAM Security Layer)
# ------------------------------------------------------------------------------
# Service account designated for the execution runbook / agent on Cloudera edge nodes
resource "google_service_account" "migration_agent" {
  account_id   = "${var.migration_name_prefix}-agent"
  display_name = "Cloudera to GCP Migration Execution Agent"
}

# Grant object administrative controls over the target GCS migration lakehouse bucket
resource "google_storage_bucket_iam_member" "agent_gcs_admin" {
  bucket = google_storage_bucket.migration_lakehouse.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.migration_agent.email}"
}

# Grant data editing privileges to allow schema creation and record insertion in BigQuery
resource "google_bigquery_dataset_iam_member" "agent_bq_editor" {
  dataset_id = google_bigquery_dataset.migration_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.migration_agent.email}"
}

# Grant job user permission at the project level to execute query validations
resource "google_project_iam_member" "agent_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.migration_agent.email}"
}

# ------------------------------------------------------------------------------
# OUTPUTS
# ------------------------------------------------------------------------------
output "gcs_target_bucket" {
  value       = google_storage_bucket.migration_lakehouse.url
  description = "Target GCS bucket path for DistCp configurations"
}

output "bq_target_dataset" {
  value       = google_bigquery_dataset.migration_dataset.dataset_id
  description = "Target BigQuery dataset ID for schema creation scripts"
}

output "migration_agent_email" {
  value       = google_service_account.migration_agent.email
  description = "Email of the service account to assign to your on-premises edge nodes"
}

# 1. Initialize backend providers and pull plugin requirements
# terraform init

# 2. Review resource state changes safely before execution
# terraform plan -var-file="variables.tfvars"

# 3. Create the resources on Google Cloud Platform
# terraform apply -var-file="variables.tfvars" -auto-approve
