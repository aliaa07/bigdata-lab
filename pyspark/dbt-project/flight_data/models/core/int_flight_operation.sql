{{ config(materialized='ephemeral') }}

-- Passenger tickets repeat operational measures. Collapse them to one flight
-- occurrence before summing distance/fuel or averaging operating metrics.
select
    flight_id,
    travel_date,
    aircraft_key,
    route_key,
    origin_airport_key,
    destination_airport_key,
    count(*) as ticket_count,
    sum(revenue) as revenue,
    max(distance) as distance,
    max(fuel_consumed_litre) as fuel_consumed_litre,
    max(avg_flight_speed_kmps) as avg_flight_speed_kmps,
    max(engine_performance) as engine_performance,
    max(turbulance) as turbulance,
    max(temp_at_dept) as temp_at_dept,
    max(taxi_duration_mins) as taxi_duration_mins,
    max(flight_duration_mins) as flight_duration_mins,
    max(case when passenger_flight_class in ('business', 'first') then 1 else 0 end) as premium_flight,
    max(case when passenger_flight_class = 'business' then 1 else 0 end) as business_class_flight,
    max(case when passenger_flight_class = 'first' then 1 else 0 end) as first_class_flight,
    sum(case when frequent_flier then 1 else 0 end) as frequent_flier_count
from {{ ref('fct_flight') }}
group by flight_id, travel_date, aircraft_key, route_key, origin_airport_key, destination_airport_key
