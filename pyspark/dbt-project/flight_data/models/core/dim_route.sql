{{ config(materialized='incremental', unique_key='route_key', file_format='delta') }}

with routes as (
    select distinct
        origin_airport,
        destination_airport
    from {{ ref('stg_flight') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['origin_airport', 'destination_airport']) }} as route_key,
    origin_airport,
    destination_airport,
    concat(origin_airport, '-', destination_airport) as route_name
from routes
{% if is_incremental() %}
where {{ dbt_utils.generate_surrogate_key(['origin_airport', 'destination_airport']) }} not in (
    select route_key from {{ this }}
)
{% endif %}