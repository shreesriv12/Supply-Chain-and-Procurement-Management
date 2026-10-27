import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

const reports = {
  spend: { label: 'Spend by category', endpoint: '/reports/spend', columns: ['month', 'category_name', 'spend', 'po_count'] },
  suppliers: { label: 'Supplier performance', endpoint: '/reports/supplier-performance', columns: ['supplier_id', 'supplier_name', 'rating', 'evaluated_orders', 'on_time_rate_pct', 'avg_quality_score', 'avg_days_late'] },
  overdue: { label: 'Overdue payments', endpoint: '/reports/overdue-payments', columns: ['invoice_no', 'supplier_name', 'due_date', 'outstanding_amount', 'status'] }
};
export default function Reports({ onQuery }) {
  const [kind, setKind] = useState('spend'); const [rows, setRows] = useState([]); const [error, setError] = useState(''); const [loading, setLoading] = useState(true);
  async function load() { setLoading(true); setError(''); try { const response = await api(reports[kind].endpoint); setRows(response.data); onQuery(response); } catch (err) { setError(err.message); } finally { setLoading(false); } }
  useEffect(() => { load(); }, [kind]);
  return <section><div className="page-title"><div><h1>Reports</h1><p>Run database views and inspect the executed SQL and returned rows below.</p></div><button className="secondary" onClick={load}>Refresh report</button></div><div className="action-card report-picker"><label>Choose report<select value={kind} onChange={e => setKind(e.target.value)}>{Object.entries(reports).map(([key, report]) => <option key={key} value={key}>{report.label}</option>)}</select></label></div>{error && <div className="error">{error}</div>}{loading ? <div className="loading">Loading…</div> : <Table rows={rows} columns={reports[kind].columns} />}</section>;
}
