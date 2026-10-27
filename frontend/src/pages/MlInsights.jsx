import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

export default function MlInsights({ onQuery }) {
  const [rows, setRows] = useState([]); const [poId, setPoId] = useState(''); const [risk, setRisk] = useState(null); const [error, setError] = useState('');
  useEffect(() => { api('/ml/forecast/reorder').then(response => { setRows(response.data); onQuery(response); }).catch(err => setError(err.message)); }, []);
  async function predict(event) { event.preventDefault(); setError(''); try { const response = await api(`/ml/predict/late/${poId}`, { method: 'POST' }); setRisk(response.data[0]); onQuery(response); } catch (err) { setError(err.message); } }
  return <section><div className="page-title"><div><h1>ML insights</h1><p>Time-aware delivery-risk classification and monthly reorder recommendations.</p></div></div><div className="grid"><article><h2>Late-delivery risk</h2><form className="inline-form" onSubmit={predict}><input value={poId} onChange={e => setPoId(e.target.value)} placeholder="Purchase order ID" type="number" required /><button>Predict risk</button></form>{risk && <div className="risk"><b>{(Number(risk.late_prob) * 100).toFixed(0)}%</b><span>late-delivery probability · {risk.model_name}</span></div>}<p className="hint">Training uses earlier supplier performance only, avoiding future-delivery leakage.</p></article><article><h2>Model availability</h2><p>Run <code>python -m app.ml.train_late</code> and <code>python -m app.ml.train_forecast</code> inside the API environment before requesting predictions.</p></article></div>{error && <div className="error">{error}</div>}<h2 className="section-heading">Suggested reorders</h2><Table rows={rows.slice(0,30)} columns={['warehouse_id','product_name','qty_on_hand','forecast_demand','reorder_level','suggested_reorder_qty']} /></section>;
}
