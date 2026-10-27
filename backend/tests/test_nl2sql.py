import pytest
from app.ai.nl2sql import validate_sql

def test_select_on_whitelisted_view_is_allowed():
    assert "LIMIT 200" in validate_sql("SELECT supplier_name FROM v_supplier_performance")
@pytest.mark.parametrize("query", [
    "DELETE FROM supplier", "SELECT * FROM supplier", "SELECT * FROM v_low_stock; DROP TABLE supplier", "SELECT * FROM v_low_stock -- ignore rules",
])
def test_prompt_injection_and_destructive_sql_are_blocked(query):
    with pytest.raises(ValueError): validate_sql(query)
