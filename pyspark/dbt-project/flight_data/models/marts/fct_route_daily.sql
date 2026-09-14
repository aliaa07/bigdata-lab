{{
    config(
        materialized='incremental',
        file_format='delta',
        unique_key='route_date_key',
        pre_hook="SET spark.databricks.delta.optimizeMetadataQuery.enabled = false"
    )
}}

with daily_flight as (
    select
        f.flight_id,
        f.route_key,
        f.travel_date,
        f.origin_airport_key,
        f.destination_airport_key,
        f.aircraft_key,
        f.distance,
        f.revenue as flight_cost,
        f.fuel_consumed_litre,
        f.avg_flight_speed_kmps,
        f.engine_performance,
        f.turbulance,
        f.temp_at_dept,
        f.taxi_duration_mins,
        f.ticket_count,
        f.business_class_flight,
        f.first_class_flight,
        f.frequent_flier_count
    from {{ ref('int_flight_operation') }} f
),

route_daily as (
    select
        travel_date,
        origin_airport_key,
        destination_airport_key,
        route_key,
        count(*) as flight_count,
        sum(distance) as total_distance_km,
        sum(flight_cost) / sum(ticket_count) as avg_flight_cost,
        sum(flight_cost) as total_revenue,
        avg(fuel_consumed_litre) as avg_fuel_consumption,
        sum(fuel_consumed_litre) as total_fuel_consumption,
        avg(avg_flight_speed_kmps) as avg_flight_speed,
        avg(engine_performance) as avg_engine_performance,
        avg(turbulance) as avg_turbulance,
        avg(temp_at_dept) as avg_temp_at_dept,
        avg(taxi_duration_mins) as avg_taxi_duration,
        sum(business_class_flight) as business_class_flights,
        sum(first_class_flight) as first_class_flights,
        sum(frequent_flier_count) as frequent_flier_count
    from daily_flight
    group by 1, 2, 3, 4
)

select
    {{ dbt_utils.generate_surrogate_key(['travel_date', 'route_key']) }} as route_date_key,
    travel_date,
    origin_airport_key,
    destination_airport_key,
    route_key,
    flight_count,
    total_distance_km,
    avg_flight_cost,
    total_revenue,
    avg_fuel_consumption,
    total_fuel_consumption,
    avg_flight_speed,
    avg_engine_performance,
    avg_turbulance,
    avg_temp_at_dept,
    avg_taxi_duration,
    business_class_flights,
    first_class_flights,
    frequent_flier_count
from route_daily
