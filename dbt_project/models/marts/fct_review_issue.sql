select c.review_id, c.listing_id, d.neighbourhood, d.room_type, c.review_date, c.issue_category, c.classifier
from {{ ref('int_reviews_classified') }} c
left join {{ ref('dim_listing') }} d on d.listing_id = c.listing_id
