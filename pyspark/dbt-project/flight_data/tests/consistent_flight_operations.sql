-- Operational values must agree across tickets on the same flight occurrence.
-- Reject conflicting source data rather than silently choosing a measurement.
select flight_id, travel_date
from {{ ref('fct_flight') }}
group by flight_id, travel_date
having count(distinct aircraft_key) <> 1
    or count(distinct route_key) <> 1
    or count(distinct distance) <> 1
    or count(distinct fuel_consumed_litre) <> 1
    or count(distinct flight_duration_mins) <> 1
    or count(distinct avg_flight_speed_kmps) <> 1
    or count(distinct engine_performance) <> 1
    or count(distinct turbulance) <> 1
    or count(distinct temp_at_dept) <> 1
    or count(distinct taxi_duration_mins) <> 1
