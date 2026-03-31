{{
    config(
        materialized='table',
        schema='MARTS'
    )
}}

WITH daily_totals AS (

    SELECT
        ingestion_date,
        SUM(market_cap_usd) AS total_market_cap_usd
    FROM {{ ref('stg_crypto_market') }}
    GROUP BY ingestion_date

)

SELECT
    s.ingestion_date                                    AS report_date,
    s.coin_id,
    s.symbol,
    s.coin_name,
    s.market_cap_usd,
    s.market_cap_rank,
    t.total_market_cap_usd,
    ROUND(
        s.market_cap_usd / NULLIF(t.total_market_cap_usd, 0) * 100,
        4
    )                                                   AS market_dominance_pct

FROM {{ ref('stg_crypto_market') }} s
INNER JOIN daily_totals t
    ON s.ingestion_date = t.ingestion_date

ORDER BY s.ingestion_date, s.market_cap_rank
