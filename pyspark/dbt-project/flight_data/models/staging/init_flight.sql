{{
  config(
    materialized='ephemeral'
  )
}}

with raw as (

    select distinct *
    from {{ source('warehouse', 'sample_flight_data') }}

),

staged as (

    select
        cast(flight_id as string)                as flight_id,
        cast(aircraft_id as string)               as aircraft_id,
        cast(itinerary_no as int)                 as itinerary_no,
        cast(ticket_no as string)                 as ticket_no,
        cast(flight_cost as decimal(12,2))        as flight_cost,
        cast(origin_airport as string)            as origin_airport,
        cast(destination_airport as string)       as destination_airport,
        cast(frequent_flier as boolean)           as frequent_flier,
        cast(travel_date as date)                 as travel_date,

        date_format(to_timestamp(departure_time, 'HH:mm:ss'), 'HH:mm:ss') as departure_time,
        hour(to_timestamp(departure_time, 'HH:mm:ss')) * 3600
            + minute(to_timestamp(departure_time, 'HH:mm:ss')) * 60
            + second(to_timestamp(departure_time, 'HH:mm:ss'))            as departure_seconds,

        to_timestamp(concat(travel_date, ' ', arrival_time), 'yyyy-MM-dd HH:mm:ss')
            + case when arrival_time < departure_time then interval 1 day else interval 0 days end
                                                   as arrival_time,
        cast(airplane_model as string)            as airplane_model,
        cast(frequent_flier_no as string)         as frequent_flier_no,
        cast(passenger_name as string)            as passenger_name,
        cast(passenger_country as string)         as passenger_country,
        cast(tail_no as string)                   as tail_no,
        cast(distance as int)                     as distance,
        cast(turbulance as int)                   as turbulance,
        cast(temp_at_dept as float)                as temp_at_dept,
        cast(fuel_consumed_litre as float)         as fuel_consumed_litre,
        cast(taxi_duration_mins as float)          as taxi_duration_mins,
        cast(avg_flight_speed_kmps as double)      as avg_flight_speed_kmps,
        cast(engine_performance as int)            as engine_performance,
        cast(passenger_dob as date)                as passenger_dob,
        cast(passenger_flight_class as string)     as passenger_flight_class

    from raw

)

select
    *,
    uuid() as uuid
from staged
