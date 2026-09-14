{{
    config(
        materialized='incremental',
        unique_key='flight_key',
        incremental_strategy='merge',
        file_format='delta',
        partition_by=['travel_date'],
        pre_hook="SET spark.databricks.delta.optimizeMetadataQuery.enabled = false"
    )
}}

with stg as (
    select * from {{ ref('stg_flight') }}
),

dim_passenger as (
    select * from {{ ref('dim_passenger') }} where dbt_valid_to is null
),

dim_aircraft as (
    select aircraft_id, aircraft_key from {{ ref('dim_aircraft') }} where dbt_valid_to is null
),

dim_airport as (
    select airport_key, airport_name from {{ ref('dim_airport') }} where dbt_valid_to is null
),

fact as (
    select
        {{ dbt_utils.generate_surrogate_key([
            's.flight_id', 
            's.travel_date',
            's.itinerary_no', 
            's.ticket_no'
        ]) }} as flight_key,

        -- foreign keys
        dp.passenger_key,
        {{ dbt_utils.generate_surrogate_key(['s.origin_airport', 's.destination_airport']) }} as route_key,
        da.aircraft_key,
        dap_orig.airport_key as origin_airport_key,
        dap_dest.airport_key as destination_airport_key,

        -- dates
        cast(s.travel_date as date) as travel_date,
        year(s.travel_date) as travel_year,
        month(s.travel_date) as travel_month,
        dayofweek(s.travel_date) as travel_dow,

        -- timestamps
        s.departure_time,
        s.arrival_time,
        s.departure_seconds,

        -- flight details
        s.flight_id,
        s.itinerary_no,
        s.ticket_no,
        s.passenger_flight_class,
        s.frequent_flier,
        s.frequent_flier_no,

        -- measures
        s.flight_cost as revenue,
        s.distance,
        s.turbulance,
        s.temp_at_dept,
        s.fuel_consumed_litre,
        s.taxi_duration_mins,
        s.avg_flight_speed_kmps,
        s.engine_performance,
        s.flight_duration_mins,
        s.revenue_per_km,
        s.fuel_per_km,

        -- metadata
        s.uuid as source_uuid,
        current_timestamp() as dbt_updated_at

    from stg s
    left join dim_passenger dp
        on dp.passenger_name = s.passenger_name
        and dp.passenger_country = s.passenger_country
        and dp.passenger_dob = s.passenger_dob
    left join dim_aircraft da
        on da.aircraft_id = s.aircraft_id
    left join dim_airport dap_orig
        on dap_orig.airport_name = s.origin_airport
    left join dim_airport dap_dest
        on dap_dest.airport_name = s.destination_airport
)

select * from fact
-- The source has no ingestion timestamp: merge all source keys to include
-- late arrivals and corrections to older travel dates.
