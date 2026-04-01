# Modern Data Stack Project

An end-to-end ELT pipeline that ingests cryptocurrency market data from the CoinGecko API into Snowflake, transforms it through staging and marts layers using dbt, orchestrates everything with Apache Airflow running in Docker, manages infrastructure with Terraform, and validates code quality with GitHub Actions CI/CD.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────────────────────┐
│  CoinGecko  │────▶│  Apache Airflow   │────▶│            Snowflake                │
│    API      │     │  (Docker)         │     │                                     │
└─────────────┘     │                   │     │  ┌─────────────┐                    │
                    │  ┌─────────────┐  │     │  │INGESTION_DB │                    │
                    │  │ Extract     │  │     │  │  └─COINGECKO │◀── Raw JSON       │
                    │  │ Stage & Load│──│────▶│  │    (VARIANT) │                    │
                    │  │ Verify      │  │     │  └─────────────┘                    │
                    │  └──────┬──────┘  │     │                                     │
                    │         │         │     │  ┌──────────────────┐               │
                    │  ┌──────▼──────┐  │     │  │CRYPTO_ANALYTICS_DB│               │
                    │  │ dbt run     │──│────▶│  │  ├─STAGING       │◀── Parsed     │
                    │  │ dbt test    │  │     │  │  └─MARTS         │◀── Aggregated │
                    │  └─────────────┘  │     │  └──────────────────┘               │
                    └──────────────────┘     └─────────────────────────────────────┘
                                                          ▲
                    ┌──────────────────┐                   │
                    │    Terraform     │───────────────────┘
                    │  (IaC)           │  Provisions databases, schemas,
                    └──────────────────┘  warehouses, roles, grants

                    ┌──────────────────┐
                    │  GitHub Actions  │  Lints Python, validates dbt,
                    │  (CI/CD)         │  checks Terraform on every PR
                    └──────────────────┘
```

## Technology Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Infrastructure | **Terraform** | Provisions all Snowflake resources (databases, schemas, warehouse, roles, grants) as code |
| Containerization | **Docker** | Hosts Airflow, Postgres (metadata DB), and Redis in isolated containers |
| Orchestration | **Apache Airflow** | Schedules daily ELT pipeline: API extraction → Snowflake load → dbt transformations |
| Data Warehouse | **Snowflake** | Stores raw data (INGESTION_DB) and transformed analytics (CRYPTO_ANALYTICS_DB) |
| Transformations | **dbt** | Parses JSON into structured tables (staging), builds business metrics (marts) |
| CI/CD | **GitHub Actions** | Runs flake8, black, dbt compile, and terraform validate on every pull request |

## Data Flow

**1. Ingestion**: Airflow calls the CoinGecko `/coins/markets` endpoint daily, fetching the top 50 cryptocurrencies by market cap. The raw JSON is written to a temp file, uploaded to a Snowflake internal stage via `PUT`, then loaded into `INGESTION_DB.COINGECKO.RAW_CRYPTO_MARKET` using `COPY INTO`. Each coin is stored as a `VARIANT` (raw JSON) row with an ingestion timestamp.

**2. Staging**: dbt reads from the raw table, flattens the JSON into typed columns (price, market cap, volume, supply metrics, all-time highs/lows), deduplicates by coin and date, and materializes as an incremental model in `CRYPTO_ANALYTICS_DB.STAGING`.

**3. Marts**: Three business-level models in `CRYPTO_ANALYTICS_DB.MARTS`:
- **daily_market_summary**: Daily snapshot per coin with price range, supply percentage, and all key metrics
- **market_dominance**: Each coin's share of total tracked market cap, using window functions
- **top_movers_daily**: Coins ranked by 24h price change (biggest gainers and losers)

**4. Testing**: 19 dbt data tests validate not-null constraints, accepted ranges (prices > 0, dominance between 0-100%), and data integrity across all layers.

## Database Architecture

The project uses a multi-database pattern that mirrors production best practices:

- **INGESTION_DB**: Shared raw data lake. One schema per source (e.g., `COINGECKO`). Raw API responses stored as-is. Designed to be reused across multiple downstream projects.
- **CRYPTO_ANALYTICS_DB**: Project-specific transformations. Contains `STAGING` (cleaned, structured data) and `MARTS` (business aggregations). Each analytics project gets its own database.

This separation means raw data is ingested once and consumed by many projects, while each project's transformations are isolated.

## Project Structure

```
modern-data-stack-project/
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                   # Snowflake resources (databases, schemas, roles, grants)
│   ├── variables.tf              # Input variables
│   └── outputs.tf                # Output values
├── airflow/                      # Orchestration
│   ├── Dockerfile                # Custom Airflow image with Snowflake + dbt
│   └── dags/
│       └── ingest_and_transform_crypto.py  # Full ELT pipeline DAG
├── dbt_project/                  # Transformations
│   ├── dbt_project.yml           # Project config
│   ├── profiles.yml              # Snowflake connection (uses env vars)
│   ├── packages.yml              # dbt_utils dependency
│   ├── macros/
│   │   └── generate_schema_name.sql  # Custom schema routing
│   └── models/
│       ├── ingestion/
│       │   └── sources.yml       # Source definitions with freshness checks
│       ├── staging/
│       │   ├── stg_crypto_market.sql   # Incremental model: JSON → structured
│       │   └── staging.yml       # Column tests
│       └── marts/
│           ├── daily_market_summary.sql
│           ├── market_dominance.sql
│           ├── top_movers_daily.sql
│           └── marts.yml         # Column tests
├── .github/workflows/
│   └── ci.yml                    # CI pipeline (lint, dbt validate, terraform validate)
├── docker-compose.yml            # Airflow services (webserver, scheduler, worker, triggerer)
└── .gitignore
```

## Setup Instructions

### Prerequisites
- Docker Desktop
- Terraform
- Git
- A Snowflake account (free trial works)

### 1. Clone and configure

```bash
git clone https://github.com/FedericoCasati/modern-data-stack-project.git
cd modern-data-stack-project
```

Create a `.env` file in the project root:

```
AIRFLOW_UID=50000
SNOWFLAKE_ACCOUNT=<your-org>-<your-account>
SNOWFLAKE_USER=AIRFLOW_DBT_USER
SNOWFLAKE_PASSWORD=<your-service-account-password>
SNOWFLAKE_WAREHOUSE=LEARNING_WH
SNOWFLAKE_ROLE=AIRFLOW_DBT_ROLE
```

### 2. Provision infrastructure

```bash
cd terraform
# Create terraform.tfvars with your Snowflake admin credentials
terraform init
terraform plan
terraform apply
cd ..
```

### 3. Start Airflow

```bash
docker compose up airflow-init    # Initialize metadata DB + admin user
docker compose up -d              # Start all services
```

Open http://localhost:8080 and log in with `airflow` / `airflow`.

### 4. Run the pipeline

Unpause the `ingest_and_transform_crypto` DAG and trigger a manual run. The pipeline will:
1. Create the raw table (if needed)
2. Extract data from CoinGecko
3. Stage and load into Snowflake via `PUT` + `COPY INTO`
4. Verify ingestion
5. Check source freshness
6. Run dbt models
7. Run dbt tests

### 5. Query the results

```sql
-- Raw data
SELECT * FROM INGESTION_DB.COINGECKO.RAW_CRYPTO_MARKET LIMIT 10;

-- Structured staging
SELECT * FROM CRYPTO_ANALYTICS_DB.STAGING.STG_CRYPTO_MARKET LIMIT 10;

-- Business metrics
SELECT * FROM CRYPTO_ANALYTICS_DB.MARTS.DAILY_MARKET_SUMMARY LIMIT 10;
SELECT * FROM CRYPTO_ANALYTICS_DB.MARTS.MARKET_DOMINANCE ORDER BY market_dominance_pct DESC LIMIT 10;
SELECT * FROM CRYPTO_ANALYTICS_DB.MARTS.TOP_MOVERS_DAILY WHERE rank_by_gain <= 5;
```

## Key Design Decisions

- **COPY INTO over INSERT**: Production Snowflake pipelines use internal stages + `COPY INTO` for idempotent, scalable loads. Raw `INSERT` statements don't scale.
- **Incremental models**: The staging model uses `is_incremental()` to only process new data, avoiding full-table scans on every run.
- **Multi-database architecture**: Ingestion is separated from project-specific transformations, allowing raw data reuse across projects.
- **Terraform for Snowflake**: All infrastructure is version-controlled and reproducible. No manual clicking in the Snowflake UI.
- **Source freshness checks**: dbt checks that ingestion data isn't stale before running transformations.
- **Failure callbacks + SLA**: Airflow logs detailed error info on task failure and flags tasks that exceed 1-hour SLA.
- **Custom schema macro**: Overrides dbt's default schema concatenation behavior to use exact schema names.

## What I Learned

- **Dependency resolution matters**: Pinning dbt and Airflow provider versions in the Dockerfile prevents 30+ minute pip backtracking during builds.
- **Ambiguous columns in incremental models**: Snowflake's merge statement during incremental runs can cause column name collisions. Aliasing source columns in the first CTE prevents this.
- **dbt schema naming**: By default, dbt prepends the target schema to custom schemas (e.g., `STAGING_MARTS`). A custom `generate_schema_name` macro is required to use exact schema names.
- **Terraform state management**: `terraform plan` before every `apply` is essential. Infrastructure changes are reviewable diffs, just like code.
- **CI catches real issues**: The GitHub Actions pipeline caught formatting issues and path configuration errors before they reached main.

## License

This project is for educational and portfolio purposes.
