# Real and Synthetic Data Methodology

The project uses two complementary data strategies.

## Synthetic PostgreSQL seed

The generated seed is the authoritative live demo database. It has 3,000 POs, related requisitions, receipts, invoices, payments, supplier evaluations, and 20,000 stock movements. This consistency is needed to demonstrate database constraints, transactions, RBAC, and the full UI lifecycle. The generator intentionally makes delivery delay depend on supplier reliability, lead time, and order size.

## Real public datasets

| Dataset | Use in this project | Why it is kept separate |
| --- | --- | --- |
| DataCo Supply Chain | Late-delivery risk model validation | It lacks the internal requisition, GRN, approval, and payment workflow. |
| M5 Forecasting Accuracy | Demand-forecast model validation | It is retail sales data, not warehouse stock movement. |
| Olist e-commerce | Supplier/seller, order, product, payment and delivery analysis | It is a marketplace model with customers and sellers rather than internal procurement roles. |

`train_real_data.py` uses chronological 80/20 splits. It saves DataCo classifier metrics and M5 forecaster MAE/MAPE metrics separately from the models trained from the live seeded database. In the report, present the synthetic model as the integrated system demonstration and real-data results as external validation evidence.
