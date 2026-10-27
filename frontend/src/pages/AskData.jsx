import { useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';
export default function AskData({ onQuery }) {
  const [question, setQuestion] = useState('Which suppliers have the best on-time delivery rate?'); const [sql, setSql] = useState(''); const [rows, setRows] = useState([]); const [error, setError] = useState('');
  async function ask(event) { event.preventDefault(); setError(''); try { const response = await api('/ai/ask-data', { method: 'POST', body: JSON.stringify({ question }) }); setRows(response.data); setSql(response.executed_sql[0]); onQuery(response); } catch (err) { setError(err.message); } }
  async function execute() { setError(''); try { const response = await api('/ai/ask-data/execute', { method: 'POST', body: JSON.stringify({ sql }) }); setRows(response.data); setSql(response.executed_sql[0]); onQuery(response); } catch (err) { setError(err.message); } }
  return <section><div className="page-title"><div><h1>Ask Data</h1><p>Generated SQL is limited to read-only reporting views.</p></div></div><article><form onSubmit={ask} className="ask-form"><input value={question} onChange={e => setQuestion(e.target.value)} /><button>Generate & run</button></form>{sql && <><label>Validated SQL<textarea value={sql} onChange={e => setSql(e.target.value)} /></label><button className="secondary" onClick={execute}>Run edited SQL</button></>}{error && <div className="error">{error}</div>}</article><div className="result-space"><Table rows={rows} /></div></section>;
}
