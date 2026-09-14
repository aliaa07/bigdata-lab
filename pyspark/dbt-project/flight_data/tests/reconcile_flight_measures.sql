-- Validate actual materialized results against the source, including cents
-- and overnight arrival times. A successful run returns no mismatches.
with expected as (
    select
        cast(flight_id as string) as flight_id,
        cast(travel_date as date) as travel_date,
        cast(itinerary_no as int) as itinerary_no,
        cast(ticket_no as string) as ticket_no,
        cast(flight_cost as decimal(12,2)) as revenue,
        pmod(
            unix_timestamp(arrival_time, 'HH:mm:ss')
            - unix_timestamp(departure_time, 'HH:mm:ss'),
            86400
        ) / 60.0 as duration
    from {{ source('warehouse', 'sample_flight_data') }}
)
select e.*
from expected e
full outer join {{ ref('fct_flight') }} f
    on e.flight_id = f.flight_id and e.travel_date = f.travel_date
    and e.itinerary_no = f.itinerary_no and e.ticket_no = f.ticket_no
where f.flight_key is null or e.flight_id is null
    or not (e.revenue <=> f.revenue)
    or not (e.duration <=> f.flight_duration_mins)
