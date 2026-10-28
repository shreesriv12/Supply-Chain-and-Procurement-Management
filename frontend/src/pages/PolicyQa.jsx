
import { useState } from 'react';
import { api } from '../lib/api';

export default function PolicyQa({ onQuery }) {
  const [file, setFile] = useState(null);
  const [question, setQuestion] = useState(
    'What payment terms are stated in the policy?'
  );
  const [answer, setAnswer] = useState(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [asking, setAsking] = useState(false);

  async function upload(event) {
    event.preventDefault();

    if (!file) {
      setError('Please select a .txt policy file first.');
      return;
    }

    setError('');
    setMessage('');
    setUploading(true);

    try {
      const authData = JSON.parse(
        localStorage.getItem('scm_auth') || 'null'
      );
      const token = authData?.access_token;

      if (!token) {
        throw new Error('Please log in again before uploading a policy.');
      }

      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch(
        'http://localhost:8000/api/ai/rag/upload',
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
          },
          body: formData,
        }
      );

      const payload = await response.json();

      if (!response.ok) {
        throw new Error(
          payload.detail || 'Policy upload failed.'
        );
      }

      const result = payload.data?.[0];

      setMessage(
        result
          ? `${result.doc_name}: ${result.chunks_indexed} chunks indexed successfully.`
          : 'Policy uploaded successfully.'
      );

      onQuery?.(payload);
    } catch (err) {
      setError(err.message || 'Unable to upload policy.');
    } finally {
      setUploading(false);
    }
  }

  async function ask(event) {
    event.preventDefault();

    const questionText = question.trim();

    if (!questionText) {
      setError('Please enter a question.');
      return;
    }

    setError('');
    setAnswer(null);
    setAsking(true);

    try {
      const response = await api('/ai/rag/ask', {
        method: 'POST',
        body: JSON.stringify({ question: questionText }),
      });

      const result = response.data?.[0];

      if (!result) {
        throw new Error(
          'No answer returned. Upload and index a policy document first.'
        );
      }

      setAnswer(result);
      onQuery?.(response);
    } catch (err) {
      setError(err.message || 'Unable to answer the policy question.');
    } finally {
      setAsking(false);
    }
  }

  return (
    <section>
      <div className="page-title">
        <div>
          <h1>Policy Q&A</h1>
          <p>
            Upload a text policy or contract, then ask questions
            based on its contents.
          </p>
        </div>
      </div>

      <div className="grid">
        <article>
          <h2>Index a policy</h2>

          <form onSubmit={upload}>
            <input
              type="file"
              accept=".txt,text/plain"
              onChange={(event) => {
                setFile(event.target.files?.[0] || null);
                setError('');
                setMessage('');
              }}
            />

            <button type="submit" disabled={uploading}>
              {uploading ? 'Indexing...' : 'Index document'}
            </button>
          </form>

          {message && <p role="status">{message}</p>}
        </article>

        <article>
          <h2>Ask a policy question</h2>

          <form onSubmit={ask}>
            <input
              type="text"
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Ask about payment terms, approvals, etc."
            />

            <button type="submit" disabled={asking}>
              {asking ? 'Asking...' : 'Ask policy'}
            </button>
          </form>

          {asking && <p>Searching policy documents for an answer...</p>}
        </article>
      </div>

      {error && (
        <div className="error" role="alert">
          {error}
        </div>
      )}

      {answer && (
        <article>
          <h2>Answer</h2>
          <p>{answer.answer || 'No answer text was returned.'}</p>

          <h2>Retrieved excerpts</h2>

          {Array.isArray(answer.sources) && answer.sources.length > 0 ? (
            answer.sources.map((source, index) => (
              <p key={source.chunk_id ?? index}>
                <b>
                  {source.doc_name || 'Policy document'}
                  {source.chunk_id != null && ` #${source.chunk_id}`}
                </b>
                {' — '}
                {source.chunk_text}
              </p>
            ))
          ) : (
            <p>No supporting excerpts were returned.</p>
          )}
        </article>
      )}
    </section>
  );
}