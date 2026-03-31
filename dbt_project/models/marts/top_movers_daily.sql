{{
    config(
        materialized='view',
        schema='MARTS'
    )
}}

SELECT
    ingestion_date                                      AS report_date,
    coin_id,
    symbol,
    coin_name,
    current_price_usd,
    price_change_pct_24h,
    total_volume_usd,
    market_cap_usd,
    market_cap_rank,
    RANK() OVER (
        PARTITION BY ingestion_date
        ORDER BY price_change_pct_24h DESC
    )                                                   AS rank_by_gain,
    RANK() OVER (
        PARTITION BY ingestion_date
        ORDER BY price_change_pct_24h ASC
    )                                                   AS rank_by_loss

FROM {{ ref('stg_crypto_market') }}
WHERE price_change_pct_24h IS NOT NULL
