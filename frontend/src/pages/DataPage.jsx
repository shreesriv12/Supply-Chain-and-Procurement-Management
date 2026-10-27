import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

export default function DataPage({ title, subtitle, endpoint, columns, onQuery, resource }) {
  const [rows, setRows] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [form, setForm] = useState(null);
  const [saving, setSaving] = useState(false);

  async function load(publishQuery = true) {
    setLoading(true); setError('');
    try {
      const query = resource?.searchable && search.trim() ? `?search=${encodeURIComponent(search.trim())}` : '';
      const response = await api(`${endpoint}${query}`);
      setRows(response.data); if (publishQuery) onQuery(response);
    } catch (err) { setError(err.message); } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, [endpoint]);
  const newRecord = () => Object.fromEntries(resource.fields.map(field => [field.name, field.default ?? '']));
  async function submit(event) {
    event.preventDefault(); setSaving(true); setError('');
    try {
      const { [resource.id]: id, ...values } = form;
      const body = Object.fromEntries(resource.fields.map(field => [field.name, field.type === 'number' && values[field.name] !== '' ? Number(values[field.name]) : (values[field.name] === '' ? null : values[field.name]) ]));
      const response = await api(id ? `${endpoint}/${id}` : endpoint, { method: id ? 'PUT' : 'POST', body: JSON.stringify(body) });
      onQuery(response); setForm(null); await load(false);
    } catch (err) { setError(err.message); } finally { setSaving(false); }
  }
  async function remove(row) {
    if (!window.confirm(`Delete ${row[resource.label]}? This cannot be undone.`)) return;
    try { const response = await api(`${endpoint}/${row[resource.id]}`, { method: 'DELETE' }); onQuery(response); await load(false); } catch (err) { setError(err.message); }
  }
  return <section>
    <div className="page-title"><div><h1>{title}</h1><p>{subtitle}</p></div><button className="secondary" onClick={load}>Refresh</button></div>
    {resource && <div className="action-card"><div className="search-row"><input value={search} onChange={e => setSearch(e.target.value)} onKeyDown={e => e.key === 'Enter' && load()} placeholder={`Search ${resource.labelPlural}`} /><button className="secondary" onClick={load}>Search</button><button onClick={() => setForm(newRecord())}>Add {resource.label}</button></div>
      {form && <form className="record-form" onSubmit={submit}><h2>{form[resource.id] ? `Edit ${resource.label}` : `New ${resource.label}`}</h2><div className="form-grid">{resource.fields.map(field => <label key={field.name}>{field.label}<input required={field.required} type={field.type || 'text'} step={field.step} value={form[field.name] ?? ''} onChange={e => setForm({ ...form, [field.name]: e.target.value })} /></label>)}</div><div className="form-actions"><button type="button" className="secondary" onClick={() => setForm(null)}>Cancel</button><button disabled={saving}>{saving ? 'Saving…' : 'Save record'}</button></div></form>}</div>}
    {error && <div className="error">{error}</div>}
    {loading ? <div className="loading">Loading…</div> : <Table rows={rows} columns={columns} renderActions={resource ? row => <><button className="table-action" onClick={() => setForm({ ...row })}>Edit</button><button className="table-action danger" onClick={() => remove(row)}>Delete</button></> : null} />}
  </section>;
}
