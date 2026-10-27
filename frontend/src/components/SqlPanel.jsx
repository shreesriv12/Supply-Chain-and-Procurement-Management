import { useState } from 'react';
export default function SqlPanel({ lastQuery }) {
  const [open, setOpen] = useState(true);
  return <aside className={`sql-panel ${open ? '' : 'collapsed'}`}>
    <button className="sql-heading" onClick={() => setOpen(!open)}>SQL panel <span>{open ? '−' : '+'}</span></button>
    {open && (lastQuery ? <>
      <pre>{lastQuery.executed_sql?.join('\n')}</pre>
      <p><b>Parameters:</b> {JSON.stringify(lastQuery.params?.[0] ?? [])}</p>
      <p>{lastQuery.duration_ms} ms · {lastQuery.rows_affected ?? 0} rows affected</p>
      <details><summary>Raw result</summary><pre>{JSON.stringify(lastQuery.data, null, 2)}</pre></details>
    </> : <p>Run an action to inspect its parameterized SQL and result.</p>)}
  </aside>;
}
