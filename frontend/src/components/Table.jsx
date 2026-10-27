export default function Table({ rows = [], columns = [] }) {
  if (!rows.length) return <div className="empty">No records found.</div>;
  const fields = columns.length ? columns : Object.keys(rows[0]);
  return <div className="table-wrap"><table><thead><tr>{fields.map(column => <th key={column}>{column.replaceAll('_', ' ')}</th>)}</tr></thead><tbody>
    {rows.map((row, index) => <tr key={row.id || row.supplier_id || row.product_id || row.po_id || row.req_id || row.invoice_id || index}>{fields.map(field => <td key={field}>{format(row[field])}</td>)}</tr>)}
  </tbody></table></div>;
}
function format(value) { if (value === null || value === undefined) return '—'; if (typeof value === 'object') return JSON.stringify(value); return String(value); }
