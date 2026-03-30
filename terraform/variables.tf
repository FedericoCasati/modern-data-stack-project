variable "snowflake_organization" {
  description = "Snowflake organization name"
  type        = string
}

variable "snowflake_account" {
  description = "Snowflake account name (not the full org-account identifier)"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake admin username for Terraform to authenticate"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake admin password"
  type        = string
  sensitive   = true
}

variable "service_account_password" {
  description = "Password for the Airflow/dbt service account user"
  type        = string
  sensitive   = true
}
