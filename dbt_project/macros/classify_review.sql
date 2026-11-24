{% macro classify_review(text_col) -%}
{%- set labels = var('issue_labels') -%}
{%- set fn = var('cortex_fn', 'ai_classify') -%}
{%- if fn == 'ai_classify' -%}
  ai_classify({{ text_col }}, [{% for l in labels %}'{{ l }}'{{ ', ' if not loop.last }}{% endfor %}]):labels[0]::string
{%- elif fn == 'ai_complete' -%}
  lower(trim(ai_complete('llama3.1-8b', 'Classify this guest review into exactly one of: {{ labels | join(', ') }}. Reply with the label only.' || chr(10) || chr(10) || 'Review: ' || {{ text_col }})))
{%- else -%}
  case when regexp_like(lower({{ text_col }}), '.*(dirty|filthy|stain|smell|roach|bug|mold).*') then 'cleanliness'
       when regexp_like(lower({{ text_col }}), '.*(noise|noisy|loud|thin walls).*') then 'noise'
       when regexp_like(lower({{ text_col }}), '.*(check.?in|lockbox|door code|locked out|key).*') then 'check_in'
       when regexp_like(lower({{ text_col }}), '.*(respond|communicat|never replied|unresponsive).*') then 'host_communication'
       when regexp_like(lower({{ text_col }}), '.*(wifi|air condition|hot water|parking|pool).*') then 'amenities'
       when regexp_like(lower({{ text_col }}), '.*(overpriced|expensive|cleaning fee|not worth).*') then 'value'
       when regexp_like(lower({{ text_col }}), '.*(far from|location|walk to).*') then 'location'
       else 'other' end
{%- endif -%}
{%- endmacro %}
