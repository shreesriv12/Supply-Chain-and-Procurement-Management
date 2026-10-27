import { useEffect, useState } from 'react';
import { BarChart, Bar, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { api } from '../lib/api';
import Table from '../components/Table';
export default function Dashboard({ onQuery }) {
  const [spend, setSpend] = useState([]); const [low, setLow] = useState([]); const [orders, setOrders] = useState([]); const [error, setError] = useState('');
  useEffect(() => { Promise.all(['/reports/spend', '/inventory/low-stock', '/orders'].map(api)).then(([a,b,c]) => { setSpend(a.data); setLow(b.data); setOrders(c.data); onQuery(c); }).catch(e => setError(e.message)); }, []);
  const monthly = Object.values(spend.reduce((all, row) => ({ ...all, [row.month]: { month: row.month, spend: (all[row.month]?.spend || 0) + Number(row.spend) } }), {}));
  return <section><div className="page-title"><div><h1>Procurement dashboard</h1><p>Operational snapshot across the procure-to-pay cycle.</p></div></div>{error && <div className="error">{error}</div>}<div className="kpis"><div><span>Purchase orders</span><b>{orders.length}</b></div><div><span>Low-stock alerts</span><b>{low.length}</b></div><div><span>Open PO value</span><b>₹{orders.filter(o => !['CLOSED','CANCELLED'].includes(o.status)).reduce((n,o) => n + Number(o.total_amount), 0).toLocaleString()}</b></div></div><div className="grid"><article className="chart-card"><h2>Monthly spend</h2><ResponsiveContainer width="100%" height={270}><BarChart data={monthly}><XAxis dataKey="month" hide /><YAxis /><Tooltip /><Bar dataKey="spend" fill="#155eef" radius={[5,5,0,0]} /></BarChart></ResponsiveContainer></article><article><h2>Low-stock alerts</h2><Table rows={low.slice(0,6)} columns={['warehouse_name','product_name','qty_on_hand','reorder_level']} /></article></div></section>;
}
