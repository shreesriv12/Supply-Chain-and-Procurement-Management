from __future__ import annotations
from datetime import date
from fastapi import APIRouter, Depends, HTTPException
from ..auth import current_user
from ..db import run_sql
from ..ml.predict import forecast_demand, late_probability

router = APIRouter(prefix="/ml", tags=["machine learning"])
LATE_FEATURE_SQL = """
WITH history AS (SELECT AVG(CASE WHEN old.delivered_date <= old.expected_date THEN 1.0 ELSE 0.0 END) prior_on_time_rate FROM purchase_order po JOIN purchase_order old ON old.supplier_id=po.supplier_id AND old.order_date<po.order_date WHERE po.po_id=%s)
SELECT s.rating supplier_rating, h.prior_on_time_rate, po.expected_date-po.order_date planned_lead_time, po.total_amount, COUNT(pi.line_no) line_count, SUM(pi.qty_ordered) total_qty, EXTRACT(MONTH FROM po.order_date)::int order_month, MIN(c.name) category, w.city warehouse_city FROM purchase_order po JOIN supplier s USING(supplier_id) JOIN warehouse w USING(warehouse_id) JOIN po_item pi USING(po_id) JOIN product p USING(product_id) JOIN category c USING(category_id) CROSS JOIN history h WHERE po.po_id=%s GROUP BY s.rating,h.prior_on_time_rate,po.expected_date,po.order_date,po.total_amount,w.city
"""
@router.post("/predict/late/{po_id}")
def predict_late(po_id: int, user: dict = Depends(current_user)):
    result = run_sql(LATE_FEATURE_SQL, [po_id, po_id], app_role=user["role"])
    if not result["data"]: raise HTTPException(404, "Purchase order not found")
    try: probability, model_name = late_probability(result["data"][0])
    except FileNotFoundError as exc: raise HTTPException(503, str(exc)) from exc
    saved = run_sql("INSERT INTO prediction (po_id,model_name,late_prob) VALUES (%s,%s,%s) RETURNING pred_id,po_id,model_name,late_prob,predicted_at", [po_id, model_name, probability], app_role=user["role"])
    saved["feature_query"] = result["executed_sql"]; return saved

@router.get("/forecast/reorder")
def reorder_suggestions(user: dict = Depends(current_user)):
    history = run_sql("""WITH monthly AS (SELECT product_id,date_trunc('month',moved_at)::date month,SUM(qty) demand FROM stock_movement WHERE movement_type='OUT' GROUP BY 1,2), ranked AS (SELECT *,ROW_NUMBER() OVER(PARTITION BY product_id ORDER BY month DESC) r FROM monthly) SELECT i.warehouse_id,i.product_id,p.name product_name,i.qty_on_hand,i.reorder_level,i.reorder_qty,COALESCE(MAX(demand) FILTER(WHERE r=1),0) lag_1,COALESCE(MAX(demand) FILTER(WHERE r=2),0) lag_2,COALESCE(MAX(demand) FILTER(WHERE r=3),0) lag_3,COALESCE(AVG(demand) FILTER(WHERE r<=3),0) rolling_3 FROM inventory i JOIN product p USING(product_id) LEFT JOIN ranked USING(product_id) GROUP BY i.warehouse_id,i.product_id,p.name,i.qty_on_hand,i.reorder_level,i.reorder_qty""", app_role=user["role"])
    suggestions = []
    for row in history["data"]:
        try: forecast = forecast_demand({"product_id": row["product_id"], "month_number": date.today().month, "lag_1": row["lag_1"], "lag_2": row["lag_2"], "lag_3": row["lag_3"], "rolling_3": row["rolling_3"]})
        except FileNotFoundError as exc: raise HTTPException(503, str(exc)) from exc
        row["forecast_demand"] = round(forecast, 1); row["suggested_reorder_qty"] = max(0, int(round(forecast + row["reorder_level"] - row["qty_on_hand"])))
        suggestions.append(row)
    history["data"] = sorted(suggestions, key=lambda item: item["suggested_reorder_qty"], reverse=True); return history
