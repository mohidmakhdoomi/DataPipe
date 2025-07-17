{{
  config(
    materialized='view',
    tags=['staging', 'events']
  )
}}

with source_data as (
    select * from {{ source('raw', 'user_events') }}
),

cleaned as (
    select
        event_id,
        user_id,
        session_id,
        lower(trim(event_type)) as event_type,
        timestamp as event_timestamp,
        page_url,
        product_id,
        search_query,
        lower(trim(device_type)) as device_type,
        lower(trim(browser)) as browser,
        ip_address,
        properties,
        created_at,
        
        -- Derived fields
        date(event_timestamp) as event_date,
        date_part('year', event_timestamp) as event_year,
        date_part('month', event_timestamp) as event_month,
        date_part('day', event_timestamp) as event_day,
        date_part('hour', event_timestamp) as event_hour,
        date_part('dow', event_timestamp) as day_of_week,
        
        -- Time of day
        case 
            when date_part('hour', event_timestamp) between 6 and 11 then 'morning'
            when date_part('hour', event_timestamp) between 12 and 17 then 'afternoon'
            when date_part('hour', event_timestamp) between 18 and 21 then 'evening'
            else 'night'
        end as time_of_day,
        
        -- Event categories
        case 
            when event_type in ('login', 'logout') then 'authentication'
            when event_type in ('page_view') then 'navigation'
            when event_type in ('product_view', 'search') then 'discovery'
            when event_type in ('add_to_cart', 'remove_from_cart') then 'cart_management'
            when event_type in ('checkout_start', 'purchase') then 'conversion'
            else 'other'
        end as event_category,
        
        -- Conversion funnel stage
        case 
            when event_type = 'page_view' then 1
            when event_type = 'product_view' then 2
            when event_type = 'add_to_cart' then 3
            when event_type = 'checkout_start' then 4
            when event_type = 'purchase' then 5
            else 0
        end as funnel_stage,
        
        -- Device category
        case 
            when device_type = 'mobile' then 'mobile'
            when device_type = 'tablet' then 'tablet'
            else 'desktop'
        end as device_category,
        
        -- Page type (extracted from URL)
        case 
            when page_url like '%/product/%' then 'product_page'
            when page_url like '%/home%' or page_url = '/' then 'home_page'
            when page_url like '%/search%' then 'search_page'
            when page_url like '%/cart%' then 'cart_page'
            when page_url like '%/checkout%' then 'checkout_page'
            else 'other_page'
        end as page_type

    from source_data
    where event_id is not null
      and user_id is not null
      and session_id is not null
      and event_timestamp is not null
)

select * from cleaned