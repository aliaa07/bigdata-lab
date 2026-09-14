-- Snapshot updates reuse ephemeral CTE names in nested scopes. Require inner
-- scope precedence on the actual dbt connection: EXCEPTION must not be used,
-- and LEGACY would silently select the outer value instead.
with precedence_probe as (
    select 1 as value
),
nested_query as (
    with precedence_probe as (
        select 2 as value
    )
    select value from precedence_probe
)
select * from nested_query where value <> 2
