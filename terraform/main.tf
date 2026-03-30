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
# INGESTION DATABASE (shared raw data lake - one schema per source)
# =============================================================================

resource "snowflake_database" "ingestion" {
  name    = "INGESTION_DB"
  comment = "Shared raw data lake - stores raw API responses, one schema per source"
}

resource "snowflake_schema" "coingecko" {
  database = snowflake_database.ingestion.name
  name     = "COINGECKO"
  comment  = "Raw data from the CoinGecko crypto market API"
}

# =============================================================================
# PROJECT DATABASE (project-specific transformations)
# =============================================================================

resource "snowflake_database" "crypto_analytics" {
  name    = "CRYPTO_ANALYTICS_DB"
  comment = "Crypto analytics project - staging and marts layers"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.crypto_analytics.name
  name     = "STAGING"
  comment  = "Cleaned and structured data - parsed JSON, deduplication"
}

resource "snowflake_schema" "marts" {
  database = snowflake_database.crypto_analytics.name
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
# INGESTION_DB GRANTS (read + write for Airflow to ingest raw data)
# =============================================================================

resource "snowflake_grant_privileges_to_account_role" "ingestion_db_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "coingecko_schema_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE STAGE"]

  on_schema {
    schema_name = "\"${snowflake_database.ingestion.name}\".\"${snowflake_schema.coingecko.name}\""
  }
}

# =============================================================================
# CRYPTO_ANALYTICS_DB GRANTS (read + write for dbt transformations)
# =============================================================================

resource "snowflake_grant_privileges_to_account_role" "crypto_analytics_db_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.crypto_analytics.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "staging_schema_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.crypto_analytics.name}\".\"${snowflake_schema.staging.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "marts_schema_usage" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  on_schema {
    schema_name = "\"${snowflake_database.crypto_analytics.name}\".\"${snowflake_schema.marts.name}\""
  }
}

# Grant SELECT on future and existing tables in COINGECKO schema
# so dbt can read raw data from the ingestion layer
resource "snowflake_grant_privileges_to_account_role" "ingestion_select_future_tables" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.ingestion.name}\".\"${snowflake_schema.coingecko.name}\""
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "ingestion_select_existing_tables" {
  account_role_name = snowflake_account_role.airflow_dbt.name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.ingestion.name}\".\"${snowflake_schema.coingecko.name}\""
    }
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
  default_namespace = "${snowflake_database.crypto_analytics.name}.STAGING"
  comment           = "Service account for Airflow and dbt"
}

resource "snowflake_grant_account_role" "role_to_service_user" {
  role_name = snowflake_account_role.airflow_dbt.name
  user_name = snowflake_user.airflow_dbt.name
}
