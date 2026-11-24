-- a singular test passes when it returns zero rows
select a.booking_id as booking_a, b.booking_id as booking_b, a.listing_id
from {{ ref('fct_booking') }} a
join {{ ref('fct_booking') }} b
  on a.listing_id = b.listing_id and a.booking_id < b.booking_id
where a.checkin_date < b.checkout_date and b.checkin_date < a.checkout_date
  and a.status <> 'cancelled' and b.status <> 'cancelled'
