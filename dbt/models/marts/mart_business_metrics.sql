{{
  config(
    materialized='table',
    tags=['marts', 'analytics', 'business_metrics']
  )
}}

with daily_metrics as (
    select
        transaction_date,
        transaction_year,
        transaction_month,
        transaction_quarter,
        day_of_week,
        day_type,
        
        -- Transaction metrics
        count(*) as total_transactions,
        count(case when is_successful then 1 end) as successful_transactions,
        sum(case when is_successful then recognized_revenue else 0 end) as daily_revenue,
        sum(case when is_successful then units_sold else 0 end) as units_sold,
        avg(case when is_successful then total_amount end) as avg_order_value,
        
        -- Customer metrics
        count(distinct user_id) as active_customers,
        count(distinct case when is_successful then user_id end) as purchasing_customers,
        
        -- Product metrics
        count(distinct product_id) as products_sold,
        
        -- Conversion metrics
        round(count(case when is_successful then 1 end) * 100.0 / nullif(count(*), 0), 2) as conversion_rate_pct

    from {{ ref('fact_transactions') }}
    group by 1, 2, 3, 4, 5, 6
),

monthly_cohorts as (
    select
        date_trunc('month', u.registration_date) as cohort_month,
        date_part('month', age(t.transaction_date, u.registration_date)) as period_number,
        count(distinct t.user_id) as customers,
        sum(case when t.is_successful then t.recognized_revenue else 0 end) as revenue

    from {{ ref('dim_users') }} u
    left join {{ ref('fact_transactions') }} t on u.user_id = t.user_id
    where t.transaction_date is not null
    group by 1, 2
),

customer_segments_summary as (
    select
        customer_segment,
        count(*) as customer_count,
        avg(total_revenue) as avg_revenue_per_customer,
        avg(total_transactions) as avg_transactions_per_customer,
        avg(avg_order_value) as avg_order_value,
        sum(total_revenue) as segment_total_revenue

    from {{ ref('dim_users') }}
    where customer_segment is not null
    group by 1
),

product_category_performance as (
    select
        product_category,
        count(*) as total_transactions,
        sum(case when is_successful then recognized_revenue else 0 end) as category_revenue,
        sum(case when is_successful then units_sold else 0 end) as units_sold,
        avg(case when is_successful then total_amount end) as avg_transaction_value,
        count(distinct user_id) as unique_customers

    from {{ ref('fact_transactions') }}
    where product_category is not null
    group by 1
),

user_tier_analysis as (
    select
        user_tier,
        count(*) as total_transactions,
        sum(case when is_successful then recognized_revenue else 0 end) as tier_revenue,
        avg(case when is_successful then total_amount end) as avg_order_value,
        count(distinct user_id) as unique_customers,
        round(count(case when is_successful then 1 end) * 100.0 / nullif(count(*), 0), 2) as conversion_rate_pct

    from {{ ref('fact_transactions') }}
    where user_tier is not null
    group by 1
),

key_metrics_summary as (
    select
        'overall' as metric_scope,
        current_date as calculation_date,
        
        -- Revenue metrics
        (select sum(total_revenue) from {{ ref('dim_users') }}) as total_revenue,
        (select avg(total_revenue) from {{ ref('dim_users') }} where total_revenue > 0) as avg_revenue_per_customer,
        (select sum(daily_revenue) from daily_metrics where transaction_date >= current_date - interval '30 days') as revenue_last_30_days,
        (select sum(daily_revenue) from daily_metrics where transaction_date >= current_date - interval '7 days') as revenue_last_7_days,
        
        -- Customer metrics
        (select count(*) from {{ ref('dim_users') }}) as total_customers,
        (select count(*) from {{ ref('dim_users') }} where total_revenue > 0) as paying_customers,
        (select count(*) from {{ ref('dim_users') }} where last_event_date >= current_date - interval '30 days') as active_customers_30d,
        (select count(*) from {{ ref('dim_users') }} where last_event_date >= current_date - interval '7 days') as active_customers_7d,
        
        -- Transaction metrics
        (select sum(total_transactions) from {{ ref('dim_users') }}) as total_transactions,
        (select sum(successful_transactions) from {{ ref('dim_users') }}) as successful_transactions,
        (select avg(avg_order_value) from {{ ref('dim_users') }} where avg_order_value > 0) as overall_avg_order_value,
        
        -- Product metrics
        (select count(*) from {{ ref('int_product_performance') }}) as total_products,
        (select count(*) from {{ ref('int_product_performance') }} where total_revenue > 0) as products_with_sales,
        
        current_timestamp as last_updated
)

-- Final output combining all metrics
select 
    'daily_metrics' as metric_type,
    transaction_date::text as metric_key,
    json_build_object(
        'total_transactions', total_transactions,
        'successful_transactions', successful_transactions,
        'daily_revenue', daily_revenue,
        'units_sold', units_sold,
        'avg_order_value', avg_order_value,
        'active_customers', active_customers,
        'conversion_rate_pct', conversion_rate_pct
    ) as metric_values,
    current_timestamp as last_updated
from daily_metrics

union all

select 
    'customer_segments' as metric_type,
    customer_segment as metric_key,
    json_build_object(
        'customer_count', customer_count,
        'avg_revenue_per_customer', avg_revenue_per_customer,
        'avg_transactions_per_customer', avg_transactions_per_customer,
        'segment_total_revenue', segment_total_revenue
    ) as metric_values,
    current_timestamp as last_updated
from customer_segments_summary

union all

select 
    'product_categories' as metric_type,
    product_category as metric_key,
    json_build_object(
        'total_transactions', total_transactions,
        'category_revenue', category_revenue,
        'units_sold', units_sold,
        'avg_transaction_value', avg_transaction_value,
        'unique_customers', unique_customers
    ) as metric_values,
    current_timestamp as last_updated
from product_category_performance

union all

select 
    'user_tiers' as metric_type,
    user_tier as metric_key,
    json_build_object(
        'total_transactions', total_transactions,
        'tier_revenue', tier_revenue,
        'avg_order_value', avg_order_value,
        'unique_customers', unique_customers,
        'conversion_rate_pct', conversion_rate_pct
    ) as metric_values,
    current_timestamp as last_updated
from user_tier_analysis

union all

select 
    'key_metrics' as metric_type,
    metric_scope as metric_key,
    json_build_object(
        'total_revenue', total_revenue,
        'avg_revenue_per_customer', avg_revenue_per_customer,
        'revenue_last_30_days', revenue_last_30_days,
        'revenue_last_7_days', revenue_last_7_days,
        'total_customers', total_customers,
        'paying_customers', paying_customers,
        'active_customers_30d', active_customers_30d,
        'active_customers_7d', active_customers_7d,
        'total_transactions', total_transactions,
        'successful_transactions', successful_transactions,
        'overall_avg_order_value', overall_avg_order_value,
        'total_products', total_products,
        'products_with_sales', products_with_sales
    ) as metric_values,
    current_timestamp as last_updated
from key_metrics_summary