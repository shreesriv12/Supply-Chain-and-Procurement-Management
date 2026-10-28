from __future__ import annotations

from .tools import check_stock, compare_suppliers, draft_po
from ..db import run_sql


def run_reorder_agent(
    product_id: int,
    warehouse_id: int,
    requested_by: int,
    quantity: int | None = None,
    trigger: str = "manual",
    force: bool = False,
) -> dict:
    """Assess inventory and create a draft PO only when appropriate.

    Manual orders against sufficient stock require an explicit ``force=True``.
    The agent never approves or sends the draft PO.
    """
    if product_id <= 0 or warehouse_id <= 0 or requested_by <= 0:
        raise ValueError("Product, warehouse, and requester IDs must be positive.")
    if quantity is not None and quantity <= 0:
        raise ValueError("Requested quantity must be greater than zero.")
    if force and trigger != "manual":
        raise ValueError("Manual override is allowed only for manual reorder runs.")

    run = run_sql(
        """INSERT INTO agent_run (triggered_by, goal, status)
           VALUES (%s, %s, 'RUNNING') RETURNING run_id""",
        [
            trigger,
            f"Assess reorder for product {product_id} in warehouse {warehouse_id}",
        ],
        app_role="admin",
    )
    run_id = run["data"][0]["run_id"]

    try:
        stock = check_stock(run_id, product_id, warehouse_id)
        if not stock:
            raise ValueError(
                "Inventory row not found for this product and warehouse."
            )

        qty_on_hand = int(stock["qty_on_hand"])
        reorder_level = int(stock["reorder_level"])
        reorder_qty = int(stock["reorder_qty"])

        if qty_on_hand < 0:
            raise ValueError("Inventory quantity cannot be negative.")
        if reorder_level < 0 or reorder_qty <= 0:
            raise ValueError("Invalid inventory reorder settings.")

        # Keep this threshold consistent with v_low_stock and the DB trigger.
        if qty_on_hand > reorder_level and not force:
            justification = (
                f"No reorder needed for product {product_id} in warehouse "
                f"{warehouse_id}. Current stock is {qty_on_hand} units and "
                f"the reorder level is {reorder_level}. No draft PO was "
                "created. To proceed despite sufficient stock, use the "
                "explicit manual override."
            )
            return run_sql(
                """UPDATE agent_run
                   SET status = 'NO_ACTION_REQUIRED',
                       draft_po_id = NULL,
                       justification = %s
                   WHERE run_id = %s
                   RETURNING *""",
                [justification, run_id],
                app_role="admin",
            )

        # Use the configured reorder quantity unless manually overridden.
        needed = quantity if quantity is not None else reorder_qty

        quantity_reason = (
            f"The manually requested quantity is {needed} units."
            if quantity is not None
            else f"The configured reorder quantity is {needed} units."
        )

        if needed <= 0:
            raise ValueError("Calculated reorder quantity must be positive.")

        suppliers = compare_suppliers(run_id, product_id)
        if not suppliers:
            raise ValueError("No active supplier can supply this product.")

        selected_supplier = suppliers[0]
        supplier_name = selected_supplier["supplier_name"]
        minimum_order_qty = int(selected_supplier.get("min_order_qty", 1))

        if needed < minimum_order_qty:
            raise ValueError(
                f"Requested quantity {needed} is below {supplier_name}'s "
                f"minimum order quantity of {minimum_order_qty}."
            )

        draft = draft_po(
            run_id,
            product_id,
            warehouse_id,
            needed,
            selected_supplier,
            requested_by,
        )
        draft_po_id = draft["po_id"]

        stock_warning = ""
        if qty_on_hand > reorder_level:
            stock_warning = (
                f"MANUAL OVERRIDE: Current stock is {qty_on_hand} units, "
                f"which is above the reorder level of {reorder_level}. "
                "Review the business need before approval. "
            )

        justification = (
            f"Product {product_id} in warehouse {warehouse_id} has "
            f"{qty_on_hand} units on hand, a reorder level of "
            f"{reorder_level}, and a configured reorder quantity of "
            f"{reorder_qty}. {stock_warning}{quantity_reason} "
            f"{supplier_name} was selected. Draft purchase order "
            f"{draft_po_id} was created for {needed} units and is awaiting "
            "manager approval; it has not been approved."
        )

        return run_sql(
            """UPDATE agent_run
               SET status = 'AWAITING_APPROVAL',
                   draft_po_id = %s,
                   justification = %s
               WHERE run_id = %s
               RETURNING *""",
            [draft_po_id, justification, run_id],
            app_role="admin",
        )

    except Exception as exc:
        run_sql(
            """UPDATE agent_run
               SET status = 'FAILED', justification = %s
               WHERE run_id = %s""",
            [str(exc), run_id],
            app_role="admin",
        )
        raise