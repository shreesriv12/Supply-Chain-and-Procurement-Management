const API = import.meta.env.VITE_API_URL || 'http://localhost:8000/api';
export const auth = {
  get: () => JSON.parse(localStorage.getItem('scm_auth') || 'null'),
  set: (value) => localStorage.setItem('scm_auth', JSON.stringify(value)),
  clear: () => localStorage.removeItem('scm_auth')
};
export async function api(path, options = {}) {
  const token = auth.get()?.access_token;
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...options.headers }
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.detail || 'Request failed');
  return payload;
}
export async function signIn(email, password) {
  const response = await fetch(`${API.replace('/api', '')}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.detail || 'Unable to sign in');
  auth.set(payload); return payload;
}
