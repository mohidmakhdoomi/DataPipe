{{
  config(
    materialized='table',
    tags=['intermediate', 'product_metrics']
  )
}}

with products_base as (
    select * from {{ ref('stg_products') }}
),

transaction_metrics as (
    select
        product_id,
        count(*) as total_transactions,
        count(case when status = 'completed' then 1 end) as successful_transactions,
        sum(case when status = 'completed' then quantity else 0 end) as total_units_sold,
        sum(case when status = 'completed' then total_amount else 0 end) as total_revenue,
        avg(case when status = 'completed' then total_amount end) as avg_transaction_value,
        avg(case when status = 'completed' then quantity end) as avg_quantity_per_transaction,
        count(distinct user_id) as unique_customers,
        min(case when status = 'completed' then created_at end) as first_sale_date,
        max(case when status = 'completed' then created_at end) as last_sale_date,
        
        -- Calculate success rate
        round(
            count(case when status = 'completed' then 1 end) * 100.0 / count(*), 2
        ) as transaction_success_rate_pct

    from {{ ref('stg_transactions') }}
    group by product_id
),

event_metrics as (
    select
        product_id,
        count(*) as total_product_events,
        count(case when event_type = 'product_view' then 1 end) as product_views,
        count(case when event_type = 'add_to_cart' then 1 end) as cart_adds,
        count(distinct user_id) as unique_viewers,
        count(distinct session_id) as unique_sessions,
        
        -- Calculate conversion rates
        round(
            count(case when event_type = 'add_to_cart' then 1 end) * 100.0 / 
            nullif(count(case when event_type = 'product_view' then 1 end), 0), 2
        ) as view_to_cart_rate_pct

    from {{ ref('stg_user_events') }}
    where product_id is not null
    group by product_id
),

profitability_metrics as (
    select
        p.product_id,
        p.price,
        p.cost,
        p.price - p.cost as profit_per_unit,
        round((p.price - p.cost) * 100.0 / nullif(p.price, 0), 2) as profit_margin_pct,
        coalesce(tm.total_units_sold, 0) * (p.price - p.cost) as total_profit

    from products_base p
    left join transaction_metrics tm on p.product_id = tm.product_id
),

performance_rankings as (
    select
        product_id,
        -- Revenue ranking
        row_number() over (order by total_revenue desc nulls last) as revenue_rank,
        -- Units sold ranking
        row_number() over (order by total_units_sold desc nulls last) as units_rank,
        -- Profit ranking
        row_number() over (order by total_profit desc nulls last) as profit_rank,
        -- View ranking
        row_number() over (order by product_views desc nulls last) as views_rank

    from transaction_metrics tm
    full outer join event_metrics em using (product_id)
    full outer join profitability_metrics pm using (product_id)
),

final as (
    select
        p.product_id,
        p.product_name as name,
        p.category,
        p.subcategory,
        p.brand,
        p.price,
        p.cost,
        p.is_active,
        p.created_at,
        
        -- Transaction performance
        coalesce(tm.total_transactions, 0) as total_transactions,
        coalesce(tm.successful_transactions, 0) as successful_transactions,
        coalesce(tm.total_units_sold, 0) as total_units_sold,
        coalesce(tm.total_revenue, 0) as total_revenue,
        coalesce(tm.avg_transaction_value, 0) as avg_transaction_value,
        coalesce(tm.avg_quantity_per_transaction, 0) as avg_quantity_per_transaction,
        coalesce(tm.unique_customers, 0) as unique_customers,
        tm.first_sale_date,
        tm.last_sale_date,
        coalesce(tm.transaction_success_rate_pct, 0) as transaction_success_rate_pct,
        
        -- Event performance
        coalesce(em.total_product_events, 0) as total_product_events,
        coalesce(em.product_views, 0) as product_views,
        coalesce(em.cart_adds, 0) as cart_adds,
        coalesce(em.unique_viewers, 0) as unique_viewers,
        coalesce(em.unique_sessions, 0) as unique_sessions,
        coalesce(em.view_to_cart_rate_pct, 0) as view_to_cart_rate_pct,
        
        -- Profitability
        pm.profit_per_unit,
        pm.profit_margin_pct,
        coalesce(pm.total_profit, 0) as total_profit,
        
        -- Performance rankings
        pr.revenue_rank,
        pr.units_rank,
        pr.profit_rank,
        pr.views_rank,
        
        -- Performance categories
        case 
            when coalesce(tm.total_revenue, 0) >= 10000 then 'high_revenue'
            when coalesce(tm.total_revenue, 0) >= 1000 then 'medium_revenue'
            when coalesce(tm.total_revenue, 0) > 0 then 'low_revenue'
            else 'no_revenue'
        end as revenue_category,
        
        case 
            when coalesce(em.product_views, 0) >= 1000 then 'high_interest'
            when coalesce(em.product_views, 0) >= 100 then 'medium_interest'
            when coalesce(em.product_views, 0) > 0 then 'low_interest'
            else 'no_interest'
        end as interest_category,
        
        case 
            when coalesce(pm.profit_margin_pct, 0) >= 50 then 'high_margin'
            when coalesce(pm.profit_margin_pct, 0) >= 20 then 'medium_margin'
            when coalesce(pm.profit_margin_pct, 0) > 0 then 'low_margin'
            else 'no_margin'
        end as margin_category,
        
        -- Days since last sale
        case 
            when tm.last_sale_date is not null 
            then date_part('day', age(current_date, tm.last_sale_date::date))
            else null 
        end as days_since_last_sale,
        
        -- Product lifecycle stage
        case 
            when p.created_at >= current_date - interval '30 days' then 'new'
            when tm.last_sale_date >= current_date - interval '30 days' then 'active'
            when tm.last_sale_date >= current_date - interval '90 days' then 'declining'
            when tm.last_sale_date is not null then 'dormant'
            else 'never_sold'
        end as lifecycle_stage

    from products_base p
    left join transaction_metrics tm on p.product_id = tm.product_id
    left join event_metrics em on p.product_id = em.product_id
    left join profitability_metrics pm on p.product_id = pm.product_id
    left join performance_rankings pr on p.product_id = pr.product_id
)

select * from final