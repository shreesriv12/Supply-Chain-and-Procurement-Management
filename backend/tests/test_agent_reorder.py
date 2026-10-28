"""Unit tests for reorder decision logic; no PostgreSQL connection is required."""
from unittest.mock import patch

import pytest

from app.ai.agent import run_reorder_agent


def stock_row(qty_on_hand=449, reorder_level=10, reorder_qty=50):
    return {
        "qty_on_hand": qty_on_hand,
        "reorder_level": reorder_level,
        "reorder_qty": reorder_qty,
        "product_name": "Product 001",
    }


def update_result(status, po_id=None, justification=""):
    return {
        "data": [{
            "run_id": 17,
            "status": status,
            "draft_po_id": po_id,
            "justification": justification,
        }],
        "executed_sql": [],
        "params": [],
        "duration_ms": 0,
        "rows_affected": 1,
    }


def run_insert_result():
    return {"data": [{"run_id": 17}], "executed_sql": [], "params": [], "duration_ms": 0, "rows_affected": 1}


def test_sufficient_stock_without_override_does_not_create_po():
    with patch("app.ai.agent.run_sql", side_effect=[run_insert_result(), update_result("NO_ACTION_REQUIRED", justification="No reorder needed")]) as sql, \
         patch("app.ai.agent.check_stock", return_value=stock_row()) as check, \
         patch("app.ai.agent.compare_suppliers") as suppliers, \
         patch("app.ai.agent.draft_po") as draft:
        result = run_reorder_agent(1, 1, 1, quantity=10, force=False)

    assert result["data"][0]["status"] == "NO_ACTION_REQUIRED"
    assert result["data"][0]["draft_po_id"] is None
    assert "NO_ACTION_REQUIRED" in sql.call_args_list[1].args[0]
    check.assert_called_once()
    suppliers.assert_not_called()
    draft.assert_not_called()


def test_manual_override_creates_draft_with_actual_quantity_and_name():
    supplier = {
        "supplier_id": 16,
        "supplier_name": "Supplier 16",
        "unit_price": 935.82,
        "lead_time_days": 8,
        "min_order_qty": 10,
        "rating": 3.5,
        "status": "ACTIVE",
    }
    draft_value = {"po_id": 3006, "status": "DRAFT", "total_amount": 9358.2}
    with patch("app.ai.agent.run_sql", side_effect=[run_insert_result(), update_result("AWAITING_APPROVAL", 3006, "ok")]) as sql, \
         patch("app.ai.agent.check_stock", return_value=stock_row()), \
         patch("app.ai.agent.compare_suppliers", return_value=[supplier]), \
         patch("app.ai.agent.draft_po", return_value=draft_value) as draft:
        run_reorder_agent(1, 1, 1, quantity=10, force=True)

    assert draft.call_args.args[3] == 10
    persisted_justification = sql.call_args_list[1].args[1][1]
    assert "Supplier 16 was selected" in persisted_justification
    assert "Supplier Supplier 16" not in persisted_justification
    assert "10 units" in persisted_justification
    assert "MANUAL OVERRIDE" in persisted_justification


def test_low_stock_uses_configured_reorder_quantity_when_unspecified():
    supplier = {
        "supplier_id": 16,
        "supplier_name": "Supplier 16",
        "unit_price": 10,
        "lead_time_days": 8,
        "min_order_qty": 5,
        "rating": 4.0,
        "status": "ACTIVE",
    }
    with patch("app.ai.agent.run_sql", side_effect=[run_insert_result(), update_result("AWAITING_APPROVAL", 3007)]), \
         patch("app.ai.agent.check_stock", return_value=stock_row(qty_on_hand=2)), \
         patch("app.ai.agent.compare_suppliers", return_value=[supplier]), \
         patch("app.ai.agent.draft_po", return_value={"po_id": 3007, "status": "DRAFT", "total_amount": 500}) as draft:
        run_reorder_agent(1, 1, 1)

    assert draft.call_args.args[3] == 50


def test_force_override_is_only_for_manual_runs():
    with pytest.raises(ValueError, match="only for manual"):
        run_reorder_agent(1, 1, 1, quantity=10, trigger="low_stock", force=True)


def test_nonpositive_requested_quantity_is_rejected_before_database_access():
    with patch("app.ai.agent.run_sql") as sql:
        with pytest.raises(ValueError, match="greater than zero"):
            run_reorder_agent(1, 1, 1, quantity=0)
    sql.assert_not_called()
