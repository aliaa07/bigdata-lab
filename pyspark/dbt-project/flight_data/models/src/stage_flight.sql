{{
    config(
    materialized='ephemeral'
    )
}}

select *
from {{ source('warehouse', 'stage_flight') }}