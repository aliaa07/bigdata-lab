with expected as (
    select passenger_key, count(*) as flights, sum(revenue) as spend
    from {{ ref('fct_flight') }} group by passenger_key
)
select e.passenger_key
from expected e
full outer join {{ ref('dim_passenger_segment') }} s
    on s.passenger_key = e.passenger_key
where e.passenger_key is null or s.passenger_key is null
    or not (e.flights <=> s.total_flights) or not (e.spend <=> s.total_spend)
