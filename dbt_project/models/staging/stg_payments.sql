select
    payment_id,
    booking_id,
    try_to_number(amount, 10, 2)    as amount,
    currency,
    try_to_timestamp_ntz(paid_at)   as paid_at,
    method
from {{ source('raw', 'payments') }}
