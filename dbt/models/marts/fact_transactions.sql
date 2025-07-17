{{
  config(
    materialized='table',
    tags=['marts', 'facts']
  )
}}

with transaction_base as (
    select * from {{ ref('stg_transactions') }}
),

user_dim as (
    select 
        user_id,
        tier,
        age_group,
        country,
        customer_segment,
        rfm_total_score
    from {{ ref('dim_users') }}
),

product_dim as (
    select 
        product_id,
        category,
        subcategory,
        brand,
        revenue_category as performance_tier
    from {{ ref('int_product_performance') }}
),

enriched_transactions as (
    select
        -- Transaction identifiers
        t.transaction_id,
        t.user_id,
        t.product_id,
        
        -- Transaction details
        t.quantity,
        t.unit_price,
        t.total_amount,
        t.discount_amount,
        t.tax_amount,
        t.status,
        t.payment_method,
        t.shipping_address,
        
        -- Derived transaction metrics
        t.subtotal,
        t.pre_tax_amount,
        t.discount_percentage,
        t.transaction_size,
        t.is_successful,
        t.recognized_revenue,
        
        -- Time dimensions
        t.transaction_date,
        t.transaction_year,
        t.transaction_month,
        t.transaction_day,
        t.transaction_hour,
        t.day_of_week,
        t.day_type,
        t.time_of_day,
        t.created_at,
        t.updated_at,
        
        -- User dimensions
        u.tier as user_tier,
        u.age_group as user_age_group,
        u.country as user_country,
        u.customer_segment,
        u.rfm_total_score as user_rfm_score,
        
        -- Product dimensions
        p.category as product_category,
        p.subcategory as product_subcategory,
        p.brand as product_brand,
        p.performance_tier as product_performance_tier,
        
        -- Business metrics
        case when t.is_successful then t.unit_price * t.quantity - (t.unit_price * t.quantity * 0.3) else 0 end as gross_profit_estimate,
        case when t.is_successful then 1 else 0 end as successful_transaction_count,
        case when t.is_successful then t.quantity else 0 end as units_sold,
        
        -- Flags and indicators
        case when t.discount_amount > 0 then true else false end as has_discount,
        case when t.quantity > 1 then true else false end as multi_item_purchase,
        case when t.total_amount > 500 then true else false end as high_value_transaction,
        
        -- Week and month identifiers for aggregations
        date_trunc('week', t.transaction_date) as transaction_week,
        date_trunc('month', t.transaction_date) as transaction_month_start,
        
        -- Quarter and year for reporting
        date_part('quarter', t.transaction_date) as transaction_quarter,
        
        current_timestamp as last_updated

    from transaction_base t
    left join user_dim u on t.user_id = u.user_id
    left join product_dim p on t.product_id = p.product_id
)

select * from enriched_transactions