{{
    config(
        materialized='incremental',
        unique_key='surrogate_key',
        schema='STAGING'
    )
}}
 
WITH raw_data AS (
 
    SELECT
        ingestion_timestamp AS src_ingestion_timestamp,
        raw_payload         AS src_raw_payload
    FROM {{ source('coingecko', 'raw_crypto_market') }}
    {% if is_incremental() %}
    WHERE ingestion_timestamp > (SELECT MAX(t.ingestion_timestamp) FROM {{ this }} t)
    {% endif %}
 
),
 
parsed AS (
 
    SELECT
        -- Identifiers
        src_raw_payload:id::STRING                          AS coin_id,
        src_raw_payload:symbol::STRING                      AS symbol,
        src_raw_payload:name::STRING                        AS coin_name,
 
        -- Pricing
        src_raw_payload:current_price::FLOAT                AS current_price_usd,
        src_raw_payload:high_24h::FLOAT                     AS high_24h_usd,
        src_raw_payload:low_24h::FLOAT                      AS low_24h_usd,
        src_raw_payload:price_change_24h::FLOAT             AS price_change_24h_usd,
        src_raw_payload:price_change_percentage_24h::FLOAT  AS price_change_pct_24h,
 
        -- Market data
        src_raw_payload:market_cap::FLOAT                   AS market_cap_usd,
        src_raw_payload:market_cap_rank::INT                AS market_cap_rank,
        src_raw_payload:total_volume::FLOAT                 AS total_volume_usd,
        src_raw_payload:circulating_supply::FLOAT           AS circulating_supply,
        src_raw_payload:total_supply::FLOAT                 AS total_supply,
        src_raw_payload:max_supply::FLOAT                   AS max_supply,
 
        -- All-time high/low
        src_raw_payload:ath::FLOAT                          AS ath_usd,
        src_raw_payload:ath_change_percentage::FLOAT        AS ath_change_pct,
        src_raw_payload:ath_date::TIMESTAMP_NTZ             AS ath_date,
        src_raw_payload:atl::FLOAT                          AS atl_usd,
        src_raw_payload:atl_change_percentage::FLOAT        AS atl_change_pct,
        src_raw_payload:atl_date::TIMESTAMP_NTZ             AS atl_date,
 
        -- Metadata
        src_raw_payload:last_updated::TIMESTAMP_NTZ         AS coin_last_updated_at,
        src_ingestion_timestamp                             AS ingestion_timestamp,
        src_ingestion_timestamp::DATE                       AS ingestion_date
 
    FROM raw_data
    WHERE src_raw_payload:id IS NOT NULL
 
),
 
deduplicated AS (
 
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY coin_id, ingestion_date
            ORDER BY ingestion_timestamp DESC
        ) AS row_num
    FROM parsed
 
)
 
SELECT
    {{ dbt_utils.generate_surrogate_key(['coin_id', 'ingestion_date']) }} AS surrogate_key,
    coin_id,
    symbol,
    coin_name,
    current_price_usd,
    high_24h_usd,
    low_24h_usd,
    price_change_24h_usd,
    price_change_pct_24h,
    market_cap_usd,
    market_cap_rank,
    total_volume_usd,
    circulating_supply,
    total_supply,
    max_supply,
    ath_usd,
    ath_change_pct,
    ath_date,
    atl_usd,
    atl_change_pct,
    atl_date,
    coin_last_updated_at,
    ingestion_timestamp,
    ingestion_date
FROM deduplicated
WHERE row_num = 1
