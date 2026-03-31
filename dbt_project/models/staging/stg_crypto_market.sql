{{
    config(
        materialized='incremental',
        unique_key='coin_id || ingestion_date',
        schema='STAGING'
    )
}}

WITH raw_data AS (

    SELECT
        ingestion_timestamp,
        raw_payload
    FROM {{ source('coingecko', 'raw_crypto_market') }}
    {% if is_incremental() %}
    WHERE ingestion_timestamp > (SELECT MAX(ingestion_timestamp) FROM {{ this }})
    {% endif %}

),

parsed AS (

    SELECT
        -- Identifiers
        raw_payload:id::STRING                          AS coin_id,
        raw_payload:symbol::STRING                      AS symbol,
        raw_payload:name::STRING                        AS coin_name,

        -- Pricing
        raw_payload:current_price::FLOAT                AS current_price_usd,
        raw_payload:high_24h::FLOAT                     AS high_24h_usd,
        raw_payload:low_24h::FLOAT                      AS low_24h_usd,
        raw_payload:price_change_24h::FLOAT             AS price_change_24h_usd,
        raw_payload:price_change_percentage_24h::FLOAT  AS price_change_pct_24h,

        -- Market data
        raw_payload:market_cap::FLOAT                   AS market_cap_usd,
        raw_payload:market_cap_rank::INT                AS market_cap_rank,
        raw_payload:total_volume::FLOAT                 AS total_volume_usd,
        raw_payload:circulating_supply::FLOAT           AS circulating_supply,
        raw_payload:total_supply::FLOAT                 AS total_supply,
        raw_payload:max_supply::FLOAT                   AS max_supply,

        -- All-time high/low
        raw_payload:ath::FLOAT                          AS ath_usd,
        raw_payload:ath_change_percentage::FLOAT        AS ath_change_pct,
        raw_payload:ath_date::TIMESTAMP_NTZ             AS ath_date,
        raw_payload:atl::FLOAT                          AS atl_usd,
        raw_payload:atl_change_percentage::FLOAT        AS atl_change_pct,
        raw_payload:atl_date::TIMESTAMP_NTZ             AS atl_date,

        -- Metadata
        raw_payload:last_updated::TIMESTAMP_NTZ         AS coin_last_updated_at,
        ingestion_timestamp,
        ingestion_timestamp::DATE                       AS ingestion_date

    FROM raw_data
    WHERE raw_payload:id IS NOT NULL

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
