{{
    config(
        materialized='ephemeral'
    )
}}

with raw as (
    select * from {{ ref('stage_flight') }}
),

cleaned as (
    select
        -- identifiers
        flight_id,
        aircraft_id,
        itinerary_no,
        ticket_no,

        -- timestamps
        departure_time,
        arrival_time,
        travel_date,

        -- dimensions
        origin_airport,
        destination_airport,
        airplane_model,
        tail_no,
        passenger_flight_class,

        -- passenger
        passenger_name,
        passenger_country,
        passenger_dob,
        frequent_flier,
        frequent_flier_no,

        -- measures
        flight_cost,
        distance,
        turbulance,
        temp_at_dept,
        fuel_consumed_litre,
        taxi_duration_mins,
        avg_flight_speed_kmps,
        engine_performance,

        -- derived
        departure_seconds,
        uuid,

        -- flight duration in minutes
        (unix_timestamp(arrival_time) - unix_timestamp(
            concat(travel_date, ' ', departure_time)
        )) / 60.0 as flight_duration_mins,

        -- revenue per km
        case when distance > 0 then flight_cost / distance end as revenue_per_km,

        -- fuel efficiency
        case when distance > 0 then fuel_consumed_litre / distance end as fuel_per_km

    from raw
    where flight_id is not null
      and travel_date is not null
)

select * from cleaned