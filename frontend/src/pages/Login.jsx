import { useState } from 'react';
export default function Login({ onLogin }) {
  const [email, setEmail] = useState('employee1@schemasquad.test'); const [password, setPassword] = useState('demo-password'); const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  async function submit(event) { event.preventDefault(); setBusy(true); setError(''); try { await onLogin(email, password); } catch (err) { setError(err.message); } finally { setBusy(false); } }
  return <div className="login"><form onSubmit={submit}><div className="brand">Schema<span>Squad</span></div><h1>Procure with clarity.</h1><p>Sign in to manage requisitions, orders, goods receipts and payments.</p><label>Email<input value={email} onChange={e => setEmail(e.target.value)} type="email" required /></label><label>Password<input value={password} onChange={e => setPassword(e.target.value)} type="password" required /></label>{error && <div className="error">{error}</div>}<button disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button><small>Demo credentials are prefilled.</small></form></div>;
}
