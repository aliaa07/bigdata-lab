{{ config(materialized='incremental', file_format='delta', unique_key='aircraft_date_key') }}

with flight_data as (
    select
        f.travel_date,
        f.aircraft_key,
        f.distance,
        f.revenue as flight_cost,
        f.fuel_consumed_litre,
        f.avg_flight_speed_kmps,
        f.engine_performance,
        f.turbulance,
        f.taxi_duration_mins,
        f.flight_duration_mins,
        f.passenger_flight_class
    from {{ ref('fct_flight') }} f
),

aircraft_daily as (
    select
        travel_date,
        aircraft_key,
        count(*) as flight_count,
        sum(distance) as total_distance_km,
        sum(flight_cost) as total_revenue,
        case when sum(distance) > 0 then sum(flight_cost) / sum(distance) end as revenue_per_km,
        sum(fuel_consumed_litre) as total_fuel_litres,
        case when sum(distance) > 0 then sum(fuel_consumed_litre) / sum(distance) end as fuel_per_km,
        avg(avg_flight_speed_kmps) as avg_flight_speed_kmps,
        avg(engine_performance) as avg_engine_performance,
        max(engine_performance) as max_engine_performance,
        min(engine_performance) as min_engine_performance,
        avg(turbulance) as avg_turbulance,
        sum(case when turbulance > 5 then 1 else 0 end) as high_turbulance_flights,
        avg(taxi_duration_mins) as avg_taxi_duration,
        avg(flight_duration_mins) as avg_flight_duration,
        sum(case when passenger_flight_class in ('business', 'first') then 1 else 0 end) as premium_flights
    from flight_data
    group by 1, 2
)

select
    {{ dbt_utils.generate_surrogate_key(['travel_date', 'aircraft_key']) }} as aircraft_date_key,
    travel_date,
    aircraft_key,
    flight_count,
    total_distance_km,
    total_revenue,
    revenue_per_km,
    total_fuel_litres,
    fuel_per_km,
    avg_flight_speed_kmps,
    avg_engine_performance,
    max_engine_performance,
    min_engine_performance,
    avg_turbulance,
    high_turbulance_flights,
    avg_taxi_duration,
    avg_flight_duration,
    premium_flights
from aircraft_daily
{% if is_incremental() %}
where travel_date >= (select max(travel_date) from {{ this }})
{% endif %}