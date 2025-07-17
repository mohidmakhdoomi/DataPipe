{{
  config(
    materialized='view',
    tags=['staging', 'users']
  )
}}

with source_data as (
    select * from {{ source('raw', 'users') }}
),

cleaned as (
    select
        user_id,
        lower(trim(email)) as email,
        initcap(trim(first_name)) as first_name,
        initcap(trim(last_name)) as last_name,
        date_of_birth,
        registration_date,
        upper(trim(country)) as country,
        initcap(trim(city)) as city,
        lower(trim(tier)) as tier,
        is_active,
        last_login,
        created_at,
        updated_at,
        
        -- Derived fields
        concat(initcap(trim(first_name)), ' ', initcap(trim(last_name))) as full_name,
        
        -- Age calculation
        date_part('year', age(current_date, date_of_birth)) as age,
        
        -- Account age in days
        date_part('day', age(current_date, registration_date::date)) as account_age_days,
        
        -- Days since last login
        case 
            when last_login is not null 
            then date_part('day', age(current_date, last_login::date))
            else null 
        end as days_since_last_login,
        
        -- User status
        case 
            when not is_active then 'inactive'
            when last_login is null then 'never_logged_in'
            when date_part('day', age(current_date, last_login::date)) <= 7 then 'active'
            when date_part('day', age(current_date, last_login::date)) <= 30 then 'dormant'
            else 'churned'
        end as user_status,
        
        -- Age group
        case 
            when date_part('year', age(current_date, date_of_birth)) < 25 then 'Gen Z'
            when date_part('year', age(current_date, date_of_birth)) < 40 then 'Millennial'
            when date_part('year', age(current_date, date_of_birth)) < 55 then 'Gen X'
            else 'Boomer'
        end as age_group

    from source_data
    where user_id is not null
      and email is not null
      and email like '%@%'  -- Basic email validation
)

select * from cleaned