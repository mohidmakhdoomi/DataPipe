-- Macro to calculate customer lifetime value
{% macro calculate_clv(revenue_column, days_column, period_days=365) %}
    case 
        when {{ days_column }} > 0 
        then round({{ revenue_column }} / ({{ days_column }} / {{ period_days }}), 2)
        else 0 
    end
{% endmacro %}

-- Macro to assign RFM scores
{% macro rfm_score(value_column, thresholds) %}
    case 
        {% for i in range(thresholds|length) %}
        when {{ value_column }} >= {{ thresholds[i] }} then {{ thresholds|length - i }}
        {% endfor %}
        else 1
    end
{% endmacro %}

-- Macro to calculate conversion rate
{% macro conversion_rate(numerator, denominator) %}
    case 
        when {{ denominator }} > 0 
        then round({{ numerator }}::numeric / {{ denominator }} * 100, 2)
        else 0 
    end
{% endmacro %}

-- Macro to categorize time periods
{% macro time_period_category(timestamp_column) %}
    case 
        when date_part('hour', {{ timestamp_column }}) between 6 and 11 then 'morning'
        when date_part('hour', {{ timestamp_column }}) between 12 and 17 then 'afternoon'
        when date_part('hour', {{ timestamp_column }}) between 18 and 21 then 'evening'
        else 'night'
    end
{% endmacro %}

-- Macro to calculate days between dates
{% macro days_between(start_date, end_date) %}
    date_part('day', age({{ end_date }}, {{ start_date }}))
{% endmacro %}

-- Macro for cohort analysis
{% macro cohort_period(registration_date, transaction_date) %}
    date_part('month', age({{ transaction_date }}, {{ registration_date }}))
{% endmacro %}