-- full_refresh=false: a stray --full-refresh must never re-bill the Cortex calls.
-- To reclassify on purpose, delete the rows first.
{{ config(materialized='incremental', incremental_strategy='merge', unique_key='review_id',
          full_refresh=false, transient=false) }}
with scored as (
    select p.review_id, p.listing_id, p.review_date, p.comment_clean,
           {{ classify_review('p.comment_clean') }}  as issue_raw,   -- evaluated once per row, so billed once per row
           '{{ var('cortex_fn', 'ai_classify') }}'   as classifier,
           current_timestamp()                       as classified_at
    from {{ source('snowpark', 'reviews_prepared') }} p
    {% if is_incremental() %}
    where p.review_id not in (select review_id from {{ this }})
    {% endif %}
)
select review_id, listing_id, review_date, comment_clean,
       iff(issue_raw in ({% for l in var('issue_labels') %}'{{ l }}'{{ ', ' if not loop.last }}{% endfor %}), issue_raw, 'other') as issue_category,
       classifier,
       classified_at
from scored
