-- the VARIANT + LATERAL FLATTEN exercise (Open-Meteo returns parallel arrays)
select
    d.value::date                                       as weather_date,
    w.payload:daily:temperature_2m_max[d.index]::float  as temp_max_c,
    w.payload:daily:temperature_2m_min[d.index]::float  as temp_min_c,
    w.payload:daily:precipitation_sum[d.index]::float   as precip_mm
from {{ source('raw', 'weather_json') }} w,
     lateral flatten(input => w.payload:daily:time) d
qualify row_number() over (partition by d.value::date order by w._loaded_at desc) = 1
