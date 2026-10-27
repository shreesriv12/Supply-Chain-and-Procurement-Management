import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';
export default function Schema({ onQuery }) {
  const [tables, setTables] = useState([]); const [selected, setSelected] = useState(''); const [columns, setColumns] = useState([]);
  useEffect(() => { api('/schema/tables').then(r => { setTables(r.data); setSelected(r.data[0]?.table_name || ''); onQuery(r); }); }, []);
  useEffect(() => { if (selected) api(`/schema/tables/${selected}/columns`).then(r => { setColumns(r.data); onQuery(r); }); }, [selected]);
  return <section><div className="page-title"><div><h1>Schema & ER model</h1><p>Browse the live PostgreSQL catalog and its procure-to-pay relationships.</p></div></div><div className="schema-grid"><article className="er"><h2>Core relationship map</h2><svg viewBox="0 0 720 320" role="img" aria-label="Procure-to-pay entity relationship map"><path d="M145 96H240M350 96H455M565 96H650M145 230H240M350 230H455M565 230H650" /><g>{[['Requisition',35,70],['Purchase order',240,70],['Goods receipt',455,70],['Invoice',650,70],['Supplier',35,205],['PO items',240,205],['Inventory',455,205],['Payment',650,205]].map(([n,x,y])=><g key={n}><rect x={x} y={y} width="110" height="52" rx="7"/><text x={x+55} y={y+30} textAnchor="middle">{n}</text></g>)}</g></svg><p>Full source diagram: <code>docs/er_diagram.svg</code></p></article><article><h2>Table browser</h2><select value={selected} onChange={e => setSelected(e.target.value)}>{tables.map(row => <option key={row.table_name}>{row.table_name}</option>)}</select><Table rows={columns} columns={['column_name','data_type','is_nullable','column_default']} /></article></div></section>;
}
