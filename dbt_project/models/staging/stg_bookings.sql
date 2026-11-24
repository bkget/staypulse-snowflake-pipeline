-- collapses the planted exact duplicates and the late status revisions (latest updated_at wins)
select
    booking_id,
    try_to_number(listing_id)::bigint           as listing_id,
    guest_id,
    try_to_date(checkin_date)                   as checkin_date,
    try_to_date(checkout_date)                  as checkout_date,
    try_to_number(nights)                       as nights,
    try_to_number(total_amount, 10, 2)          as total_amount,
    lower(status)                               as status,
    try_to_timestamp_ntz(booked_at)             as booked_at,
    try_to_timestamp_ntz(updated_at)            as updated_at
from {{ source('raw', 'bookings') }}
qualify row_number() over (
    partition by booking_id order by try_to_timestamp_ntz(updated_at) desc, _loaded_at desc
) = 1
