
import { useState } from 'react';
import { api } from '../lib/api';
import Table from '../components/Table';

const reports = {
  spend: {
    label: 'Spend by category',
    endpoint: '/reports/spend',
  },
  suppliers: {
    label: 'Supplier performance',
    endpoint: '/reports/supplier-performance',
  },
  overdue: {
    label: 'Overdue payments',
    endpoint: '/reports/overdue-payments',
  },
};

export default function Reports({ onQuery }) {
  const [kind, setKind] = useState('spend');
  const [rows, setRows] = useState([]);
  const [executedSql, setExecutedSql] = useState([]);
  const [duration, setDuration] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [hasRun, setHasRun] = useState(false);

  async function loadReport() {
    setLoading(true);
    setError('');
    setHasRun(false);
    setRows([]);
    setExecutedSql([]);
    setDuration(null);

    try {
      // Calls the real FastAPI endpoint and PostgreSQL database.
      const response = await api(reports[kind].endpoint);

      setRows(response.data ?? []);
      setExecutedSql(response.executed_sql ?? []);
      setDuration(response.duration_ms ?? null);
      setHasRun(true);

      // Updates the existing application SQL panel, if connected.
      if (onQuery) {
        onQuery(response);
      }
    } catch (err) {
      setError(err.message || 'Unable to execute the report.');
    } finally {
      setLoading(false);
    }
  }

  const columns =
    rows.length > 0 ? Object.keys(rows[0]) : [];

  return (
    <section className="reports-page">
      <div className="page-title">
        <div>
          <h1>Reports</h1>
          <p>
            Run database views and inspect the executed SQL
            and returned rows below.
          </p>
        </div>

        <button
          type="button"
          className="secondary"
          onClick={loadReport}
          disabled={loading}
        >
          {loading ? 'Running...' : 'Refresh report'}
        </button>
      </div>

      <article className="report-picker">
        <h2>Select a database report</h2>

        <label>
          Choose report

          <select
            value={kind}
            onChange={(event) => {
              setKind(event.target.value);
              setRows([]);
              setExecutedSql([]);
              setDuration(null);
              setError('');
              setHasRun(false);
            }}
            disabled={loading}
          >
            {Object.entries(reports).map(([key, report]) => (
              <option key={key} value={key}>
                {report.label}
              </option>
            ))}
          </select>
        </label>

        <div className="report-actions">
          <button
            type="button"
            onClick={loadReport}
            disabled={loading}
          >
            {loading ? 'Executing query...' : 'Run Report'}
          </button>
        </div>
      </article>

      {error && (
        <div className="error" role="alert">
          Report failed: {error}
        </div>
      )}

      {loading && (
        <div className="loading">
          Executing query against PostgreSQL...
        </div>
      )}

      {hasRun && !loading && (
        <>
          <article className="report-results">
            <div className="report-section-heading">
              <div>
                <h2>{reports[kind].label}</h2>
                <p>Actual rows returned by the database</p>
              </div>

              <span className="report-count">
                {rows.length} rows
              </span>
            </div>

            {duration !== null && (
              <p className="report-duration">
                Query execution time: {duration} ms
              </p>
            )}

            <div className="report-table">
              {rows.length > 0 ? (
                <Table
                  rows={rows}
                  columns={columns}
                />
              ) : (
                <div className="empty">
                  Query executed successfully. No records found.
                </div>
              )}
            </div>
          </article>

          <article className="report-sql">
            <div className="report-section-heading">
              <div>
                <h2>Executed SQL</h2>
                <p>
                  SQL statement returned by the backend
                </p>
              </div>
            </div>

            {executedSql.length > 0 ? (
              executedSql.map((query, index) => (
                <pre
                  className="report-sql-code"
                  key={`${index}-${query}`}
                >
                  <code>{query}</code>
                </pre>
              ))
            ) : (
              <p>
                The backend did not return SQL metadata.
              </p>
            )}
          </article>
        </>
      )}
    </section>
  );
}