-- delete+insert by day. A day must be recomputed whole, so we restate every day touched by a recent update.
-- This is the series FORECAST trains on. Compare its run time and bytes written with the MERGE in fct_booking.
{{ config(materialized='incremental', incremental_strategy='delete+insert', unique_key='booking_date') }}
select
    booked_at::date                   as booking_date,
    count(*)                          as bookings_created,
    count_if(status <> 'cancelled')   as bookings_active,
    sum(total_amount)                 as gross_amount
from {{ ref('fct_booking') }}
{% if is_incremental() %}
where booked_at::date in (
    select distinct booked_at::date
    from {{ ref('fct_booking') }}
    where updated_at >= (select dateadd(day, -3, max(updated_at)) from {{ ref('fct_booking') }})
)
{% endif %}
group by 1
