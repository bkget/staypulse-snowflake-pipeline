-- current version only, history stays in the snapshot
select
    listing_id, name, neighbourhood, room_type, accommodates, price_usd, host_is_superhost, review_score_rating,
    dbt_valid_from as valid_from
from {{ ref('snap_listing') }}
where dbt_valid_to = to_timestamp_ntz('9999-12-31')
