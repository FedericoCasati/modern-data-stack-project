{{
    config(
        materialized='table',
        schema='MARTS'
    )
}}

SELECT
    ingestion_date                                      AS report_date,
    coin_id,
    symbol,
    coin_name,
    current_price_usd,
    high_24h_usd,
    low_24h_usd,
    high_24h_usd - low_24h_usd                         AS price_range_usd,
    price_change_24h_usd,
    price_change_pct_24h,
    market_cap_usd,
    market_cap_rank,
    total_volume_usd,
    circulating_supply,
    total_supply,
    max_supply,
    CASE
        WHEN max_supply IS NOT NULL AND max_supply > 0
        THEN ROUND(circulating_supply / max_supply * 100, 2)
        ELSE NULL
    END                                                 AS pct_supply_in_circulation

FROM {{ ref('stg_crypto_market') }}
