-- reviewer_name is dropped here on purpose, it is personal data we do not need downstream
select
    try_to_number(id)::bigint         as review_id,
    try_to_number(listing_id)::bigint as listing_id,
    try_to_date("DATE")               as review_date,
    comments                          as comment_text
from {{ source('raw', 'reviews') }}
where try_to_number(id) is not null
qualify row_number() over (partition by try_to_number(id) order by _source_file desc) = 1   -- safe if both snapshots were loaded
