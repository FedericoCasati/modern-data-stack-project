terraform {
  required_version = ">= 1.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.14"
    }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  password          = var.snowflake_password
}

# =============================================================================
# WAREHOUSE
# =============================================================================

resource "snowflake_warehouse" "learning" {
  name           = "LEARNING_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = true
  comment        = "Warehouse for the Modern Data Stack learning project"
}

# =============================================================================
# DATABASE
# =============================================================================

resource "snowflake_database" "learning" {
  name    = "LEARNING_DB"
  comment = "Database for the Modern Data Stack learning project"
}

# =============================================================================
# SCHEMAS (Medallion layers using dbt naming conventions)
# =============================================================================

resource "snowflake_schema" "ingestion" {
  database = snowflake_database.learning.name
  name     = "INGESTION"
  comment  = "Raw data layer - stores API responses as-is"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.learning.name
  name     = "STAGING"
  comment  = "Cleaned and structured data - parsed JSON, deduplication"
}

resource "snowflake_schema" "marts" {
  database = snowflake_database.learning.name
  name     = "MARTS"
  comment  = "Business-level aggregations and metrics - consumption ready"
}

# =============================================================================
# SERVICE ROLE (for Airflow and dbt to use)
# =============================================================================

resource "snowflake_account_role" "airflow_dbt" {
  name    = "AIRFLOW_DBT_ROLE"
  comment = "Service role for Airflow orchestration and dbt transformations"
}

# Grant role to SYSADMIN so admins can manage objects created by this role
resource "snowflake_grant_account_role" "airflow_dbt_to_sysadmin" {
  role_name        = snowflake_account_role.airflow_dbt.name
  parent_role_name = "SYSADMIN"
}

# =============================================================================
# WAREHOUSE GRANTS
# =============================================================================

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.learning.name
  }
}

# =============================================================================
# DATABASE GRANTS
# =============================================================================

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.learning.name
  }
}

# =============================================================================
# SCHEMA GRANTS
# =============================================================================

locals {
  schemas = {
    ingestion = snowflake_schema.ingestion.name
    staging   = snowflake_schema.staging.name
    marts     = snowflake_schema.marts.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  for_each          = local.schemas
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.learning.name}\".\"${each.value}\""
  }
}

# =============================================================================
# SERVICE USER
# =============================================================================

resource "snowflake_user" "airflow_dbt" {
  name              = "AIRFLOW_DBT_USER"
  login_name        = "AIRFLOW_DBT_USER"
  password          = var.service_account_password
  default_warehouse = snowflake_warehouse.learning.name
  default_role      = snowflake_account_role.airflow_dbt.name
  default_namespace = "${snowflake_database.learning.name}.STAGING"
  comment           = "Service account for Airflow and dbt"
}

resource "snowflake_grant_account_role" "role_to_service_user" {
  role_name = snowflake_account_role.airflow_dbt.name
  user_name = snowflake_user.airflow_dbt.name
}
