"""
DAG: ingest_and_transform_crypto
Full ELT pipeline: extracts crypto market data from CoinGecko API,
loads it into Snowflake (INGESTION_DB), then runs dbt transformations
(CRYPTO_ANALYTICS_DB staging + marts) and tests.
"""

from datetime import datetime, timedelta
import json
import logging
import os
import tempfile

import requests
import snowflake.connector
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SNOWFLAKE_CONFIG = {
    "account": os.environ["SNOWFLAKE_ACCOUNT"],
    "user": os.environ["SNOWFLAKE_USER"],
    "password": os.environ["SNOWFLAKE_PASSWORD"],
    "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
    "role": os.environ["SNOWFLAKE_ROLE"],
}

COINGECKO_URL = "https://api.coingecko.com/api/v3/coins/markets"
COINGECKO_PARAMS = {
    "vs_currency": "usd",
    "order": "market_cap_desc",
    "per_page": 50,
    "page": 1,
    "sparkline": "false",
}

TARGET_DATABASE = "INGESTION_DB"
TARGET_SCHEMA = "COINGECKO"
TARGET_TABLE = "RAW_CRYPTO_MARKET"
FULLY_QUALIFIED_TABLE = f"{TARGET_DATABASE}.{TARGET_SCHEMA}.{TARGET_TABLE}"

DBT_PROJECT_DIR = "/opt/airflow/dbt_project"

# ---------------------------------------------------------------------------
# Failure callback
# ---------------------------------------------------------------------------
def on_failure_callback(context):
    """Log detailed failure information."""
    task_instance = context.get("task_instance")
    dag_id = context.get("dag").dag_id
    task_id = task_instance.task_id
    execution_date = context.get("execution_date")
    exception = context.get("exception")

    logger.error(
        f"TASK FAILED | dag={dag_id} | task={task_id} | "
        f"execution_date={execution_date} | error={exception}"
    )


# ---------------------------------------------------------------------------
# DAG default args
# ---------------------------------------------------------------------------
default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
    "on_failure_callback": on_failure_callback,
    "sla": timedelta(hours=1),
}


# ---------------------------------------------------------------------------
# Ingestion task functions
# ---------------------------------------------------------------------------
def create_table_if_not_exists():
    """Ensure the raw landing table exists in Snowflake."""
    conn = snowflake.connector.connect(**SNOWFLAKE_CONFIG)
    try:
        cur = conn.cursor()
        cur.execute(f"USE DATABASE {TARGET_DATABASE}")
        cur.execute(f"USE SCHEMA {TARGET_SCHEMA}")
        cur.execute(f"""
            CREATE TABLE IF NOT EXISTS {FULLY_QUALIFIED_TABLE} (
                ingestion_timestamp  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                source_api           VARCHAR DEFAULT 'coingecko',
                raw_payload          VARIANT
            )
        """)
        logger.info(f"Table {FULLY_QUALIFIED_TABLE} is ready.")
    finally:
        conn.close()


def extract_from_api(**context):
    """Call CoinGecko API and return JSON response."""
    logger.info("Calling CoinGecko /coins/markets endpoint...")
    response = requests.get(COINGECKO_URL, params=COINGECKO_PARAMS, timeout=30)
    response.raise_for_status()

    data = response.json()
    logger.info(f"Received {len(data)} coins from CoinGecko.")

    context["ti"].xcom_push(key="raw_json", value=json.dumps(data))


def stage_and_load(**context):
    """Write JSON to a temp file, PUT to Snowflake stage, COPY INTO table."""
    raw_json = context["ti"].xcom_pull(key="raw_json", task_ids="extract_from_api")
    if not raw_json:
        raise ValueError("No data received from extract task.")

    records = json.loads(raw_json)
    ndjson_lines = [json.dumps(record) for record in records]
    ndjson_content = "\n".join(ndjson_lines)

    conn = snowflake.connector.connect(**SNOWFLAKE_CONFIG)
    try:
        cur = conn.cursor()
        cur.execute(f"USE DATABASE {TARGET_DATABASE}")
        cur.execute(f"USE SCHEMA {TARGET_SCHEMA}")

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as tmp:
            tmp.write(ndjson_content)
            tmp_path = tmp.name

        logger.info(f"Wrote {len(records)} records to {tmp_path}")

        cur.execute(
            f"PUT 'file://{tmp_path}' @%{TARGET_TABLE} AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
        )
        logger.info("PUT to stage completed.")

        cur.execute(f"""
            COPY INTO {FULLY_QUALIFIED_TABLE} (raw_payload)
            FROM @%{TARGET_TABLE}
            FILE_FORMAT = (TYPE = JSON STRIP_OUTER_ARRAY = FALSE)
            ON_ERROR = 'CONTINUE'
        """)
        copy_result = cur.fetchall()
        logger.info(f"COPY INTO result: {copy_result}")

        cur.execute(f"REMOVE @%{TARGET_TABLE}")
        logger.info("Stage cleaned up.")

        os.unlink(tmp_path)

    finally:
        conn.close()


def verify_ingestion():
    """Run a count query to verify data landed in the table."""
    conn = snowflake.connector.connect(**SNOWFLAKE_CONFIG)
    try:
        cur = conn.cursor()
        cur.execute(f"SELECT COUNT(*) FROM {FULLY_QUALIFIED_TABLE}")
        total_rows = cur.fetchone()[0]
        logger.info(f"Total rows in {FULLY_QUALIFIED_TABLE}: {total_rows}")

        cur.execute(f"""
            SELECT COUNT(*)
            FROM {FULLY_QUALIFIED_TABLE}
            WHERE ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
        """)
        recent_rows = cur.fetchone()[0]
        logger.info(f"Rows ingested in the last hour: {recent_rows}")

        if recent_rows == 0:
            raise ValueError("No rows were ingested in the last hour!")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="ingest_and_transform_crypto",
    default_args=default_args,
    description="Full ELT pipeline: CoinGecko API → Snowflake → dbt staging & marts",
    schedule_interval="0 6 * * *",  # Daily at 6 AM UTC
    start_date=datetime(2026, 3, 31),
    catchup=False,
    tags=["elt", "ingestion", "dbt", "coingecko", "snowflake"],
) as dag:

    # ---- Ingestion tasks ----
    t_create_table = PythonOperator(
        task_id="create_table_if_not_exists",
        python_callable=create_table_if_not_exists,
    )

    t_extract = PythonOperator(
        task_id="extract_from_api",
        python_callable=extract_from_api,
    )

    t_load = PythonOperator(
        task_id="stage_and_load",
        python_callable=stage_and_load,
    )

    t_verify_ingestion = PythonOperator(
        task_id="verify_ingestion",
        python_callable=verify_ingestion,
    )

    # ---- dbt tasks ----
    t_dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt source freshness",
    )

    t_dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt run",
    )

    t_dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt test",
    )

    # ---- Task dependencies ----
    # Ingestion chain
    t_create_table >> t_extract >> t_load >> t_verify_ingestion

    # dbt chain (runs after ingestion completes)
    t_verify_ingestion >> t_dbt_source_freshness >> t_dbt_run >> t_dbt_test
