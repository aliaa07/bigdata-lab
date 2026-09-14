{% snapshot dim_passenger %}

{{
    config(
        target_schema=target.schema,
        unique_key='passenger_key',
        strategy='check',
        file_format='delta',
        check_cols=['frequent_flier', 'frequent_flier_no'],
        invalidate_hard_deletes=true
    )
}}

with ranked as (
select sub.*,
     row_number() over (partition by sub.passenger_key order by travel_date desc, flight_id desc, itinerary_no desc, ticket_no desc) as rn
from (
    select
        {{ dbt_utils.generate_surrogate_key(['passenger_name', 'passenger_dob', 'passenger_country']) }} as passenger_key,
        passenger_name,
        passenger_country,
        passenger_dob,
        frequent_flier,
        frequent_flier_no,
        flight_id,
        itinerary_no,
        ticket_no,
        travel_date
    from {{ ref('stg_flight') }}) sub
)
select
    passenger_key,
    passenger_name,
    passenger_country,
    passenger_dob,
    frequent_flier,
    frequent_flier_no
from ranked
where rn = 1

{% endsnapshot %}
