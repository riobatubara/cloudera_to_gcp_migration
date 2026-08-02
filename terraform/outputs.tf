output "gcs_bucket_name" {
  description = "The name of the GCS bucket used for HDFS data migration staging."
  value       = google_storage_bucket.migration_bucket.name
}

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset where Hive tables are migrated."
  value       = google_bigquery_dataset.migration_dataset.dataset_id
}

output "dataproc_cluster_name" {
  description = "The name of the provisioned Dataproc cluster running Apache Spark/Hadoop."
  value       = google_dataproc_cluster.migration_cluster.name
}

output "migration_service_account_email" {
  description = "The email of the dedicated IAM service account handling data transfer."
  value       = google_service_account.migration_sa.email
}
