{{
  config(
    materialized='table',
    tags=['intermediate', 'user_metrics']
  )
}}

with users_base as (
    select * from {{ ref('stg_users') }}
),

transaction_metrics as (
    select
        user_id,
        count(*) as total_transactions,
        count(case when status = 'completed' then 1 end) as successful_transactions,
        sum(case when status = 'completed' then total_amount else 0 end) as total_revenue,
        avg(case when status = 'completed' then total_amount end) as avg_order_value,
        sum(case when status = 'completed' then quantity else 0 end) as total_items_purchased,
        count(distinct case when status = 'completed' then product_id end) as unique_products_purchased,
        min(case when status = 'completed' then created_at end) as first_purchase_date,
        max(case when status = 'completed' then created_at end) as last_purchase_date,
        
        -- Calculate success rate
        round(
            count(case when status = 'completed' then 1 end) * 100.0 / count(*), 2
        ) as success_rate_pct

    from {{ ref('stg_transactions') }}
    group by user_id
),

event_metrics as (
    select
        user_id,
        count(*) as total_events,
        count(distinct session_id) as total_sessions,
        count(distinct date(event_timestamp)) as active_days,
        count(case when event_type = 'page_view' then 1 end) as page_views,
        count(case when event_type = 'product_view' then 1 end) as product_views,
        count(case when event_type = 'add_to_cart' then 1 end) as cart_adds,
        count(case when event_type = 'purchase' then 1 end) as purchase_events,
        min(event_timestamp) as first_event_date,
        max(event_timestamp) as last_event_date,
        
        -- Calculate conversion rates
        round(
            count(case when event_type = 'product_view' then 1 end) * 100.0 / 
            nullif(count(case when event_type = 'page_view' then 1 end), 0), 2
        ) as product_view_rate_pct,
        
        round(
            count(case when event_type = 'add_to_cart' then 1 end) * 100.0 / 
            nullif(count(case when event_type = 'product_view' then 1 end), 0), 2
        ) as cart_conversion_rate_pct,
        
        round(
            count(case when event_type = 'purchase' then 1 end) * 100.0 / 
            nullif(count(case when event_type = 'add_to_cart' then 1 end), 0), 2
        ) as purchase_conversion_rate_pct,
        
        -- Average events per session
        round(count(*) * 1.0 / nullif(count(distinct session_id), 0), 2) as avg_events_per_session

    from {{ ref('stg_user_events') }}
    group by user_id
),

rfm_calculations as (
    select
        user_id,
        -- Recency: days since last purchase
        case 
            when last_purchase_date is not null 
            then date_part('day', age(current_date, last_purchase_date::date))
            else null 
        end as recency_days,
        
        -- Frequency: number of successful transactions
        successful_transactions as frequency,
        
        -- Monetary: total revenue
        total_revenue as monetary_value

    from transaction_metrics
),

final as (
    select
        u.user_id,
        u.full_name,
        u.email,
        u.age,
        u.age_group,
        u.tier,
        u.country,
        u.city,
        u.user_status,
        u.account_age_days,
        u.days_since_last_login,
        u.registration_date,
        
        -- Transaction metrics
        coalesce(tm.total_transactions, 0) as total_transactions,
        coalesce(tm.successful_transactions, 0) as successful_transactions,
        coalesce(tm.total_revenue, 0) as total_revenue,
        coalesce(tm.avg_order_value, 0) as avg_order_value,
        tm.last_purchase_date,
        tm.first_purchase_date,
        coalesce(tm.total_items_purchased, 0) as total_items_purchased,
        coalesce(tm.unique_products_purchased, 0) as unique_products_purchased,
        coalesce(tm.success_rate_pct, 0) as success_rate_pct,
        
        -- Event metrics
        coalesce(em.total_events, 0) as total_events,
        coalesce(em.total_sessions, 0) as total_sessions,
        coalesce(em.active_days, 0) as active_days,
        coalesce(em.page_views, 0) as page_views,
        coalesce(em.product_views, 0) as product_views,
        coalesce(em.cart_adds, 0) as cart_adds,
        coalesce(em.purchase_events, 0) as purchase_events,
        em.last_event_date,
        em.first_event_date,
        coalesce(em.product_view_rate_pct, 0) as product_view_rate_pct,
        coalesce(em.cart_conversion_rate_pct, 0) as cart_conversion_rate_pct,
        coalesce(em.purchase_conversion_rate_pct, 0) as purchase_conversion_rate_pct,
        coalesce(em.avg_events_per_session, 0) as avg_events_per_session,
        
        -- RFM metrics
        rfm.recency_days,
        rfm.frequency,
        rfm.monetary_value

    from users_base u
    left join transaction_metrics tm on u.user_id = tm.user_id
    left join event_metrics em on u.user_id = em.user_id
    left join rfm_calculations rfm on u.user_id = rfm.user_id
)

select * from final