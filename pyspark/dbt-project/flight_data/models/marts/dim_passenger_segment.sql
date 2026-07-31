{{
    config(
        materialized='incremental',
        file_format='delta',
        unique_key='passenger_segment_key'
    )
}}

with passenger_stats as (
    select
        f.passenger_key,
        count(*) as total_flights,
        sum(f.revenue) as total_spend,
        avg(f.revenue) as avg_spend_per_flight,
        sum(f.distance) as total_distance_km,
        count(case when f.passenger_flight_class in ('business','first') then 1 end) as premium_flights,
        count(case when f.frequent_flier then 1 end) as frequent_flier_flights,
        min(f.travel_date) as first_flight_date,
        max(f.travel_date) as last_flight_date,
        datediff(max(f.travel_date), min(f.travel_date)) as customer_lifetime_days
    from {{ ref('fct_flight') }} f
    {% if is_incremental() %}
    where f.travel_date >= (select coalesce(max(last_flight_date), date('1900-01-01')) from {{ this }})
    {% endif %}
    group by f.passenger_key
),

passenger_attrs as (
    select
        dp.passenger_key,
        dp.passenger_country,
        dp.passenger_dob,
        dp.frequent_flier,
        dp.frequent_flier_no
    from {{ ref('dim_passenger') }} dp
),

segments as (
    select
        ps.*,
        pa.passenger_country,
        pa.passenger_dob,
        pa.frequent_flier,
        pa.frequent_flier_no,
        datediff(ps.last_flight_date, pa.passenger_dob) / 365.25 as passenger_age,
        case
            when ps.total_flights >= 10 and ps.total_spend >= 50000 then 'vip'
            when ps.total_flights >= 5 and ps.total_spend >= 10000 then 'frequent'
            when ps.total_flights >= 2 then 'regular'
            else 'occasional'
        end as segment,
        case
            when datediff(ps.last_flight_date, pa.passenger_dob) / 365.25 < 25 then 'young_adult'
            when datediff(ps.last_flight_date, pa.passenger_dob) / 365.25 < 40 then 'adult'
            when datediff(ps.last_flight_date, pa.passenger_dob) / 365.25 < 60 then 'middle_aged'
            else 'senior'
        end as age_group
    from passenger_stats ps
    join passenger_attrs pa on pa.passenger_key = ps.passenger_key
)

select
    {{ dbt_utils.generate_surrogate_key(['passenger_key', 'segment']) }} as passenger_segment_key,
    passenger_key,
    passenger_country,
    passenger_dob,
    frequent_flier,
    frequent_flier_no,
    passenger_age,
    segment,
    age_group,
    total_flights,
    total_spend,
    avg_spend_per_flight,
    total_distance_km,
    premium_flights,
    frequent_flier_flights,
    first_flight_date,
    last_flight_date,
    customer_lifetime_days,
    current_timestamp() as dbt_updated_at
from segments