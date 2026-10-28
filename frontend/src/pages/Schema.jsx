
import { useEffect, useState } from 'react';
import { api, API } from '../lib/api';
import Table from '../components/Table';

export default function Schema({ onQuery }) {
  const [tables, setTables] = useState([]);
  const [selected, setSelected] = useState('');
  const [columns, setColumns] = useState([]);

  useEffect(() => {
    api('/schema/tables').then(r => {
      setTables(r.data);
      setSelected(r.data[0]?.table_name || '');
      onQuery(r);
    });
  }, []);

  useEffect(() => {
    if (selected) {
      api(`/schema/tables/${selected}/columns`).then(r => {
        setColumns(r.data);
        onQuery(r);
      });
    } else {
      setColumns([]);
    }
  }, [selected]);

  // Main ER diagram served by the backend API
  const diagramUrl = `${API}/schema/er-diagram`;

  // Additional ER diagram served from the frontend public folder
  const secondDiagramUrl = '/docs/er_diagram_extra.svg';

  const diagramStyle = {
    display: 'block',
    width: '100%',
    height: 'auto',
    maxHeight: '680px',
    objectFit: 'contain',
    objectPosition: 'top',
    margin: '16px 0',
    border: '1px solid #eaecf0',
    borderRadius: '8px',
    background: '#fff'
  };

  return (
    <section>
      <div className="page-title">
        <div>
          <h1>Schema &amp; ER model</h1>
          <p>
            Browse the live PostgreSQL catalog and its
            procure-to-pay relationships.
          </p>
        </div>
      </div>

      <div className="schema-grid">
        <article className="er">
          {/* Main ER Diagram */}
          <h2>Core relationship map</h2>
          <p>Procure-to-pay entity relationship map</p>

          <a
            href={diagramUrl}
            target="_blank"
            rel="noreferrer"
          >
            <img
              src={diagramUrl}
              alt="Complete Supply Chain and Procurement Management ER diagram"
              loading="lazy"
              style={diagramStyle}
            />
          </a>

          <p>
            <a
              href={diagramUrl}
              target="_blank"
              rel="noreferrer"
            >
              Open the complete ER diagram (SVG)
            </a>
          </p>

          <p>
            <a
              href={diagramUrl}
              download="er_diagram.svg"
            >
              Download the complete ER diagram (SVG)
            </a>
          </p>

          <hr />

          {/* Additional ER Diagram */}
          <h2>Additional ER diagram</h2>
          <p>Additional procure-to-pay ER model</p>

          <a
            href={secondDiagramUrl}
            target="_blank"
            rel="noreferrer"
          >
            <img
              src={secondDiagramUrl}
              alt="Additional Supply Chain and Procurement Management ER diagram"
              loading="lazy"
              style={diagramStyle}
            />
          </a>

          <p>
            <a
              href={secondDiagramUrl}
              target="_blank"
              rel="noreferrer"
            >
              Open the second ER diagram (SVG)
            </a>
          </p>

          <p>
            <a
              href={secondDiagramUrl}
              download="er_diagram_extra.svg"
            >
              Download the second ER diagram (SVG)
            </a>
          </p>
        </article>

        {/* Database Table Browser */}
        <article>
          <h2>Table browser</h2>

          <select
            value={selected}
            onChange={e => setSelected(e.target.value)}
          >
            {tables.map(row => (
              <option
                key={row.table_name}
                value={row.table_name}
              >
                {row.table_name}
              </option>
            ))}
          </select>

          <Table
            rows={columns}
            columns={[
              'column_name',
              'data_type',
              'is_nullable',
              'column_default'
            ]}
          />
        </article>
      </div>
    </section>
  );
}