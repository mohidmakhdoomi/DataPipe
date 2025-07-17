{{
  config(
    materialized='view',
    tags=['staging', 'transactions']
  )
}}

with source_data as (
    select * from {{ source('raw', 'transactions') }}
),

cleaned as (
    select
        transaction_id,
        user_id,
        product_id,
        quantity,
        unit_price,
        total_amount,
        discount_amount,
        tax_amount,
        lower(trim(status)) as status,
        lower(trim(payment_method)) as payment_method,
        shipping_address,
        created_at,
        updated_at,
        
        -- Derived fields
        round(unit_price * quantity, 2) as subtotal,
        round(total_amount - tax_amount + discount_amount, 2) as pre_tax_amount,
        round(discount_amount / nullif(unit_price * quantity, 0) * 100, 2) as discount_percentage,
        
        -- Transaction size categories
        case 
            when total_amount < 25 then 'small'
            when total_amount < 100 then 'medium'
            when total_amount < 500 then 'large'
            else 'extra_large'
        end as transaction_size,
        
        -- Time dimensions
        date(created_at) as transaction_date,
        date_part('year', created_at) as transaction_year,
        date_part('month', created_at) as transaction_month,
        date_part('day', created_at) as transaction_day,
        date_part('hour', created_at) as transaction_hour,
        date_part('dow', created_at) as day_of_week,
        
        -- Day type
        case 
            when date_part('dow', created_at) in (0, 6) then 'weekend'
            else 'weekday'
        end as day_type,
        
        -- Time of day
        case 
            when date_part('hour', created_at) between 6 and 11 then 'morning'
            when date_part('hour', created_at) between 12 and 17 then 'afternoon'
            when date_part('hour', created_at) between 18 and 21 then 'evening'
            else 'night'
        end as time_of_day,
        
        -- Success indicator
        case 
            when lower(status) = 'completed' then true
            else false
        end as is_successful,
        
        -- Revenue recognition
        case 
            when lower(status) = 'completed' then total_amount
            else 0
        end as recognized_revenue

    from source_data
    where transaction_id is not null
      and user_id is not null
      and product_id is not null
      and quantity > 0
      and unit_price > 0
)

select * from cleaned