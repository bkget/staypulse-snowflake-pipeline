-- every live booking is paid in full, nothing else is checked
select booking_id, total_amount, paid_amount
from {{ ref('fct_booking') }}
where status in ('confirmed', 'completed') and abs(paid_amount - total_amount) > 0.01
