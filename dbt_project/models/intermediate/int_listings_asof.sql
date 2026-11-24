-- Derives effective_at: the first snapshot date of the current run of identical tracked attributes.
-- Unchanged listings keep an old effective_at, changed listings get the new snapshot date.
{{ config(materialized='ephemeral') }}
with tracked as (
    select *,
           md5(concat_ws('|',
               coalesce(price_usd::string, ''), coalesce(room_type, ''), coalesce(accommodates::string, ''),
               coalesce(host_is_superhost::string, ''), coalesce(neighbourhood, ''))) as attr_hash
    from {{ ref('stg_listings') }}
),
flagged as (
    select *,
           iff(attr_hash = lag(attr_hash) over (partition by listing_id order by snapshot_date), 0, 1) as changed
    from tracked
),
islands as (
    select *,
           sum(changed) over (partition by listing_id order by snapshot_date rows unbounded preceding) as island
    from flagged
),
dated as (
    -- the window must run before the snapshot_date filter below, or effective_at would always equal the filtered date
    select *,
           min(snapshot_date) over (partition by listing_id, island)::timestamp_ntz as effective_at
    from islands
)
select * exclude (attr_hash, changed, island)
from dated
where snapshot_date = '{{ var('snapshot_date') }}'::date
