{{
  config(
    materialized='view',
    tags=['staging', 'products']
  )
}}

with source_data as (
    select * from {{ source('raw', 'products') }}
),

cleaned as (
    select
        product_id,
        trim(name) as product_name,
        lower(trim(category)) as category,
        lower(trim(subcategory)) as subcategory,
        price,
        cost,
        upper(trim(brand)) as brand,
        trim(description) as description,
        is_active,
        created_at,
        updated_at,
        
        -- Derived fields
        round(price - cost, 2) as gross_profit,
        round((price - cost) / nullif(price, 0) * 100, 2) as margin_percentage,
        
        -- Price tiers
        case 
            when price < 50 then 'budget'
            when price < 200 then 'mid_range'
            when price < 500 then 'premium'
            else 'luxury'
        end as price_tier,
        
        -- Product age in days
        date_part('day', age(current_date, created_at)) as product_age_days,
        
        -- Product lifecycle stage
        case 
            when date_part('day', age(current_date, created_at)) <= 30 then 'new'
            when date_part('day', age(current_date, created_at)) <= 365 then 'established'
            else 'mature'
        end as lifecycle_stage,
        
        -- Category grouping
        case 
            when lower(category) in ('electronics', 'books') then 'digital_lifestyle'
            when lower(category) in ('clothing', 'sports') then 'fashion_fitness'
            when lower(category) = 'home' then 'home_living'
            else 'other'
        end as category_group

    from source_data
    where product_id is not null
      and name is not null
      and price > 0
      and cost >= 0
)

select * from cleaned