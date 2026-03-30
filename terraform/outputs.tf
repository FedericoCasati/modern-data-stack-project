output "snowflake_account_identifier" {
  description = "Full Snowflake account identifier (org-account)"
  value       = "${var.snowflake_organization}-${var.snowflake_account}"
}

output "ingestion_database" {
  description = "Name of the shared ingestion database"
  value       = snowflake_database.ingestion.name
}

output "project_database" {
  description = "Name of the crypto analytics project database"
  value       = snowflake_database.crypto_analytics.name
}

output "warehouse_name" {
  description = "Name of the Snowflake warehouse"
  value       = snowflake_warehouse.learning.name
}

output "schema_names" {
  description = "Names of all schemas across both databases"
  value = {
    ingestion_coingecko = "${snowflake_database.ingestion.name}.${snowflake_schema.coingecko.name}"
    project_staging     = "${snowflake_database.crypto_analytics.name}.${snowflake_schema.staging.name}"
    project_marts       = "${snowflake_database.crypto_analytics.name}.${snowflake_schema.marts.name}"
  }
}

output "service_user" {
  description = "Service account username for Airflow/dbt"
  value       = snowflake_user.airflow_dbt.name
}

output "service_role" {
  description = "Service role name"
  value       = snowflake_account_role.airflow_dbt.name
}
