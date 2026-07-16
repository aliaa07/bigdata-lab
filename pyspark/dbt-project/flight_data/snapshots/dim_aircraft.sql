{% snapshot scd_dim_aircraft %}

{{
    config(
        target_schema='warehouse',
        unique_key='aircraft_id',
        strategy='check',
        file_format='delta',
        check_cols=['airport','airplane_model',
                    'avg_flight_cost',
                    'total_distance',
                    'avg_fuel_consumption',
                    'avg_flight_speed_kmps',
                    'max_engine_performance',
                    'min_engine_performance'],
        invalidate_hard_deletes=true
    )
}}

with possible_pr as (
    SELECT aircraft_id, max(struct(cnt, airport)).airport AS airport
    FROM (
        SELECT aircraft_id, origin_airport AS airport, COUNT(*) AS cnt
        FROM {{ ref('stage_flight') }}
        GROUP BY aircraft_id, origin_airport

        UNION

        SELECT aircraft_id, destination_airport AS airport, COUNT(*) AS cnt
        FROM {{ ref('stage_flight') }}
        GROUP BY aircraft_id, destination_airport
    ) t
    GROUP BY aircraft_id)
select
    f.aircraft_id,
    pp.airport as airport,
    f.airplane_model,
    avg(f.flight_cost) avg_flight_cost,
    sum(f.distance) total_distance,
    avg(f.fuel_consumed_litre) avg_fuel_consumption,
    avg(f.avg_flight_speed_kmps) avg_flight_speed_kmps,
    max(f.engine_performance) as max_engine_performance,
    min(f.engine_performance) as min_engine_performance
from {{ ref('stage_flight') }} f
join possible_pr pp on pp.aircraft_id = f.aircraft_id
group by
    f.aircraft_id,
    pp.airport,
    f.airplane_model

{% endsnapshot %}