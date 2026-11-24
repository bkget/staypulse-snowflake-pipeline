-- snapshot date comes from the staged file path, not from a column
select
    regexp_substr(_source_file, 'snapshot=([0-9-]{10})', 1, 1, 'e', 1)::date            as snapshot_date,
    try_to_number(id)::bigint                                                         as listing_id,
    name,
    neighbourhood_cleansed                                                            as neighbourhood,
    room_type,
    try_to_number(accommodates)                                                       as accommodates,
    try_to_number(replace(replace(price, '$', ''), ',', ''), 10, 2)                   as price_usd,
    (host_is_superhost = 't')                                                         as host_is_superhost,
    try_to_number(review_scores_rating, 4, 2)                                         as review_score_rating
from {{ source('raw', 'listings') }}
where try_to_number(id) is not null
