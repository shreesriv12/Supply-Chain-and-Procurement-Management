
import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

export default function Agent({ onQuery }) {
  const [product, setProduct] = useState('1');
  const [warehouse, setWarehouse] = useState('1');
  const [quantity, setQuantity] = useState('');
  const [force, setForce] = useState(false);
  const [runs, setRuns] = useState([]);
  const [error, setError] = useState('');

  async function load() {
    try {
      const response = await api('/ai/agent/runs');
      setRuns(response.data);
      onQuery(response);
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function run(event) {
    event.preventDefault();
    setError('');

    try {
      const response = await api('/ai/agent/reorder', {
        method: 'POST',
        body: JSON.stringify({
          product_id: Number(product),
          warehouse_id: Number(warehouse),
          ...(quantity ? { quantity: Number(quantity) } : {}),
          force: force,
        }),
      });

      onQuery(response);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <section>
      <div className="page-title">
        <div>
          <h1>Procurement agent</h1>
          <p>
            Creates a DRAFT PO only; a manager must approve it separately.
          </p>
        </div>
      </div>

      <article>
        <form className="agent-form" onSubmit={run}>
          <label>
            Product ID
            <input
              type="number"
              value={product}
              onChange={(e) => setProduct(e.target.value)}
              min="1"
              required
            />
          </label>

          <label>
            Warehouse ID
            <input
              type="number"
              value={warehouse}
              onChange={(e) => setWarehouse(e.target.value)}
              min="1"
              required
            />
          </label>

          <label>
            Quantity (optional)
            <input
              type="number"
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              min="1"
            />
          </label>

          <label className="force-reorder-option">
            <input
              type="checkbox"
              checked={force}
              onChange={(e) => setForce(e.target.checked)}
            />
            Force manual reorder even when stock is at or above reorder level
          </label>

          <button type="submit">Create draft recommendation</button>
        </form>

        {error && <div className="error">{error}</div>}
      </article>

      <h2 className="section-heading">Approval queue</h2>

      <Table
        rows={runs}
        columns={[
          'run_id',
          'triggered_by',
          'goal',
          'status',
          'draft_po_id',
          'justification',
          'created_at',
        ]}
      />
    </section>
  );
}
