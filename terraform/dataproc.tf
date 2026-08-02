# Dataproc Cluster Configuration for Cloudera Workloads
resource "google_dataproc_cluster" "cloudera_migrated_cluster" {
  name     = var.dataproc_cluster_name
  project  = var.project_id
  region   = var.region

  cluster_config {
    staging_bucket = google_storage_bucket.migration_bucket.name

    # Set up component software configuration matching common Cloudera distributions
    software_config {
      image_version = "2.1-debian11" # Standard image containing Hadoop 3.2 and Spark 3.3
      optional_components = [
        "JUPYTER",
        "ZEPPELIN"
      ]
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "false"
        "hive:hive.metastore.uris"             = var.hive_metastore_uri
      }
    }

    # Master Node Configuration (NameNode / ResourceManager equivalent)
    master_config {
      num_instances = 1
      machine_type  = var.dataproc_master_machine_type
      disk_config {
        boot_disk_type    = "pd-balanced"
        boot_disk_size_gb = 100
      }
    }

    # Worker Node Configuration (DataNode / NodeManager equivalent)
    worker_config {
      num_instances = var.dataproc_worker_count
      machine_type  = var.dataproc_worker_machine_type
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 200
      }
    }

    # Preemptible/Secondary Worker configuration for cost-optimized scaling
    secondary_worker_config {
      num_instances = var.dataproc_secondary_worker_count
      machine_type  = var.dataproc_worker_machine_type
    }

    # Network configuration
    gce_cluster_config {
      service_account = google_service_account.migration_sa.email
      # Grant full API access scopes to let Dataproc communicate with GCS/BigQuery via IAM
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }

  depends_on = [
    google_storage_bucket.migration_bucket,
    google_service_account.migration_sa
  ]
}
