{{ config(
    materialized='ephemeral'
) }}

select *
from {{ source('warehouse', 'raw_flight') }}