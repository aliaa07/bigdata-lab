{% snapshot dim_aircraft %}

{{
    config(
        target_schema='warehouse',
        unique_key='aircraft_key',
        strategy='check',
        file_format='delta',
        check_cols=['airplane_model'],
        invalidate_hard_deletes=true
    )
}}

with ranked as (
    select
        {{ dbt_utils.generate_surrogate_key(['aircraft_id']) }} as aircraft_key,
        aircraft_id,
        airplane_model,
        row_number() over (
            partition by aircraft_id
            order by travel_date desc
        ) as rn
    from {{ ref('stg_flight') }}
)
select
    aircraft_key,
    aircraft_id,
    airplane_model
from ranked
where rn = 1

{% endsnapshot %}