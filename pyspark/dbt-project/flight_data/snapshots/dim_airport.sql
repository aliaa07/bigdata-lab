{% snapshot dim_airport %}

{{
    config(
        target_schema='warehouse',
        unique_key='airport_key',
        strategy='check',
        file_format='delta',
        check_cols=['airport_name'],
        invalidate_hard_deletes=true
    )
}}

with airports as (
    select distinct origin_airport as airport_name from {{ ref('stg_flight') }}
    union
    select distinct destination_airport as airport_name from {{ ref('stg_flight') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['airport_name']) }} as airport_key,
    airport_name
from airports

{% endsnapshot %}