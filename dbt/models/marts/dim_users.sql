{{
  config(
    materialized='table',
    tags=['marts', 'dimensions']
  )
}}

with user_metrics as (
    select * from {{ ref('int_user_metrics') }}
),

rfm_scores as (
    select
        user_id,
        -- RFM scoring (1-5 scale, 5 being best)
        case 
            when recency_days <= 30 then 5
            when recency_days <= 60 then 4
            when recency_days <= 90 then 3
            when recency_days <= 180 then 2
            else 1
        end as recency_score,
        
        case 
            when frequency >= 10 then 5
            when frequency >= 5 then 4
            when frequency >= 3 then 3
            when frequency >= 1 then 2
            else 1
        end as frequency_score,
        
        case 
            when monetary_value >= 1000 then 5
            when monetary_value >= 500 then 4
            when monetary_value >= 200 then 3
            when monetary_value >= 50 then 2
            when monetary_value > 0 then 1
            else 0
        end as monetary_score

    from user_metrics
),

user_segments as (
    select
        user_id,
        recency_score,
        frequency_score,
        monetary_score,
        
        -- Combined RFM score
        (recency_score + frequency_score + monetary_score) as rfm_total_score,
        
        -- Customer segments based on RFM
        case 
            when recency_score >= 4 and frequency_score >= 4 and monetary_score >= 4 then 'champions'
            when recency_score >= 3 and frequency_score >= 3 and monetary_score >= 3 then 'loyal_customers'
            when recency_score >= 4 and frequency_score <= 2 then 'new_customers'
            when recency_score >= 3 and frequency_score >= 2 and monetary_score <= 2 then 'potential_loyalists'
            when recency_score >= 3 and frequency_score <= 2 and monetary_score <= 2 then 'promising'
            when recency_score <= 2 and frequency_score >= 3 and monetary_score >= 3 then 'need_attention'
            when recency_score <= 2 and frequency_score >= 2 and monetary_score >= 2 then 'about_to_sleep'
            when recency_score <= 2 and frequency_score <= 2 and monetary_score >= 3 then 'at_risk'
            when recency_score <= 1 and frequency_score >= 2 then 'cannot_lose_them'
            when recency_score >= 2 and frequency_score <= 1 and monetary_score <= 1 then 'hibernating'
            else 'lost'
        end as customer_segment

    from rfm_scores
),

final as (
    select
        um.user_id,
        um.full_name,
        um.email,
        um.age,
        um.age_group,
        um.tier,
        um.country,
        um.city,
        um.user_status,
        um.account_age_days,
        um.days_since_last_login,
        um.registration_date,
        
        -- Transaction summary
        um.total_transactions,
        um.successful_transactions,
        um.total_revenue,
        um.avg_order_value,
        um.last_purchase_date,
        um.first_purchase_date,
        um.total_items_purchased,
        um.unique_products_purchased,
        
        -- Engagement summary
        um.total_events,
        um.total_sessions,
        um.active_days,
        um.page_views,
        um.product_views,
        um.cart_adds,
        um.purchase_events,
        um.last_event_date,
        um.first_event_date,
        
        -- Calculated metrics
        um.success_rate_pct,
        um.product_view_rate_pct,
        um.cart_conversion_rate_pct,
        um.purchase_conversion_rate_pct,
        um.avg_events_per_session,
        
        -- RFM analysis
        um.recency_days,
        um.frequency,
        um.monetary_value,
        us.recency_score,
        us.frequency_score,
        us.monetary_score,
        us.rfm_total_score,
        us.customer_segment,
        
        -- Customer lifetime value (simple calculation)
        case 
            when um.account_age_days > 0 
            then round(um.total_revenue / (um.account_age_days / 365.0), 2)
            else 0 
        end as annual_clv_estimate,
        
        -- Engagement score (0-100)
        least(100, round(
            (um.total_sessions * 2 + 
             um.active_days * 3 + 
             um.product_views * 0.5 + 
             um.cart_adds * 2 + 
             um.purchase_events * 5) / 
            greatest(1, um.account_age_days / 30.0), 0
        )) as engagement_score,
        
        -- Risk flags
        case when um.days_since_last_login > 90 then true else false end as churn_risk_flag,
        case when um.success_rate_pct < 50 then true else false end as low_success_flag,
        case when um.total_revenue = 0 and um.account_age_days > 30 then true else false end as non_purchaser_flag,
        
        current_timestamp as last_updated

    from user_metrics um
    left join user_segments us on um.user_id = us.user_id
)

select * from final