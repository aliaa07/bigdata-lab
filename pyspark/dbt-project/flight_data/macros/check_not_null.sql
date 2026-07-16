{% macro check_not_null(model) %}
    select * from {{ model }}
    where
        {% for col in adapter.get_columns_in_relation(model) -%}
            {% if col.column != 'dbt_valid_to' %}
                {{ col.column }} is null or
            {% endif %}
        {% endfor %}
        false
{% endmacro %}