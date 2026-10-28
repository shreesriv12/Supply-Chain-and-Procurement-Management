import { useEffect, useRef, useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

export default function MlInsights({ onQuery }) {
  const [rows, setRows] = useState([]);
  const [poId, setPoId] = useState('');
  const [risk, setRisk] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [predicting, setPredicting] = useState(false);

  // Keep the latest callback without re-running the loading effect.
  const onQueryRef = useRef(onQuery);
  onQueryRef.current = onQuery;

  // Load reorder suggestions once when this page mounts.
  useEffect(() => {
    let cancelled = false;

    async function loadReorders() {
      setLoading(true);
      setError('');

      try {
        const response = await api('/ml/forecast/reorder');

        console.log('Reorder API response:', response);

        const records = Array.isArray(response?.data)
          ? response.data
          : Array.isArray(response)
            ? response
            : [];

        if (!cancelled) {
          setRows(records);
          onQueryRef.current?.(response);
        }
      } catch (err) {
        console.error('Failed to load reorder suggestions:', err);

        if (!cancelled) {
          setError(
            err.message || 'Failed to load reorder suggestions.'
          );
          setRows([]);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadReorders();

    return () => {
      cancelled = true;
    };
  }, []);

  // Predict late-delivery risk for the entered purchase order.
  async function predict(event) {
    event.preventDefault();
    setError('');
    setRisk(null);
    setPredicting(true);

    try {
      const response = await api(`/ml/predict/late/${poId}`, {
        method: 'POST',
      });

      const prediction = Array.isArray(response?.data)
        ? response.data[0]
        : response?.data;

      if (!prediction) {
        throw new Error('No prediction data returned by the API.');
      }

      setRisk(prediction);
      onQueryRef.current?.(response);
    } catch (err) {
      console.error('Failed to predict delivery risk:', err);
      setError(err.message || 'Failed to predict delivery risk.');
    } finally {
      setPredicting(false);
    }
  }

  return (
    <section>
      <div className="page-title">
        <div>
          <h1>ML insights</h1>
          <p>
            Time-aware delivery-risk classification and monthly reorder
            recommendations.
          </p>
        </div>
      </div>

      <div className="grid">
        <article>
          <h2>Late-delivery risk</h2>

          <form className="inline-form" onSubmit={predict}>
            <input
              value={poId}
              onChange={(event) => setPoId(event.target.value)}
              placeholder="Purchase order ID"
              type="number"
              min="1"
              required
            />

            <button type="submit" disabled={predicting}>
              {predicting ? 'Predicting...' : 'Predict risk'}
            </button>
          </form>

          {risk && (
            <div className="risk">
              <b>
                {(Number(risk.late_prob) * 100).toFixed(0)}%
              </b>
              <span>
                late-delivery probability · {risk.model_name}
              </span>
            </div>
          )}

          <p className="hint">
            Training uses earlier supplier performance only, avoiding
            future-delivery leakage.
          </p>
        </article>

        <article>
          <h2>Model availability</h2>

          <p>
            Prediction endpoints require their trained model files to be
            available in the backend environment.
          </p>

          <p className="hint">
            If a model is missing, train it using
            <code> python -m app.ml.train_late </code>
            and
            <code> python -m app.ml.train_forecast </code>
            in the backend environment.
          </p>
        </article>
      </div>

      {error && <div className="error">{error}</div>}

      <h2 className="section-heading">Suggested reorders</h2>

      {loading ? (
        <p className="hint">Loading reorder suggestions...</p>
      ) : rows.length > 0 ? (
        <Table
          rows={rows.slice(0, 30)}
          columns={[
            'warehouse_id',
            'product_name',
            'qty_on_hand',
            'forecast_demand',
            'reorder_level',
            'suggested_reorder_qty',
          ]}
        />
      ) : (
        !error && (
          <div className="empty">
            No reorder records returned by the API.
          </div>
        )
      )}
    </section>
  );
}
