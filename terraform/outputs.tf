output "snowflake_account_identifier" {
  description = "Full Snowflake account identifier (org-account)"
  value       = "${var.snowflake_organization}-${var.snowflake_account}"
}

output "database_name" {
  description = "Name of the Snowflake database"
  value       = snowflake_database.learning.name
}

output "warehouse_name" {
  description = "Name of the Snowflake warehouse"
  value       = snowflake_warehouse.learning.name
}

output "schema_names" {
  description = "Names of all schemas"
  value = {
    ingestion = snowflake_schema.ingestion.name
    staging   = snowflake_schema.staging.name
    marts     = snowflake_schema.marts.name
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
