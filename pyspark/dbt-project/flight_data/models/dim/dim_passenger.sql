{{
    config(
        materialized='incremental',
        unique_key='passenger_key',
        incremental_strategy='merge',
        file_format='delta'
    )
}}

select
    {{ dbt_utils.generate_surrogate_key(['passenger_name','passenger_country','passenger_dob']) }} as passenger_key,
    passenger_name,
    passenger_country,
    passenger_dob,
    passenger_flight_class
from (
    select distinct
        passenger_name,
        passenger_country,
        passenger_dob,
        passenger_flight_class
    from {{ ref('stage_flight') }}
) sub
{% if is_incremental() %}
where not exists (
    select 1 from {{ this }} t
    where t.passenger_key = {{ dbt_utils.generate_surrogate_key(['sub.passenger_name','sub.passenger_country','sub.passenger_dob']) }}
)
{% endif %}