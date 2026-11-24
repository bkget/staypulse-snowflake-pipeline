-- incremental MERGE. Only mutable columns are updated, the 3-day lookback catches late revisions
{{ config(materialized='incremental', incremental_strategy='merge', unique_key='booking_id',
          merge_update_columns=['status', 'paid_amount', 'updated_at'], on_schema_change='fail') }}
with paid as (
    select booking_id, sum(amount) as paid_amount
    from {{ ref('stg_payments') }}
    group by 1
)
select b.booking_id, b.listing_id, b.guest_id, b.checkin_date, b.checkout_date, b.nights, b.total_amount,
       coalesce(p.paid_amount, 0) as paid_amount, b.status, b.booked_at, b.updated_at
from {{ ref('stg_bookings') }} b
left join paid p on p.booking_id = b.booking_id
{% if is_incremental() %}
where b.updated_at >= (select dateadd(day, -3, max(updated_at)) from {{ this }})
{% endif %}
