import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';
export default function DataPage({ title, subtitle, endpoint, columns, onQuery, action }) {
  const [rows, setRows] = useState([]); const [error, setError] = useState(''); const [loading, setLoading] = useState(true);
  async function load() { setLoading(true); try { const response = await api(endpoint); setRows(response.data); onQuery(response); } catch (err) { setError(err.message); } finally { setLoading(false); } }
  useEffect(() => { load(); }, [endpoint]);
  return <section><div className="page-title"><div><h1>{title}</h1><p>{subtitle}</p></div><button className="secondary" onClick={load}>Refresh</button></div>{action && <div className="action-card">{action(load)}</div>}{error && <div className="error">{error}</div>}{loading ? <div className="loading">Loading…</div> : <Table rows={rows} columns={columns} />}</section>;
}
