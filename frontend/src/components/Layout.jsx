const navigation = [
  ['dashboard', 'Dashboard'], ['suppliers', 'Suppliers'], ['products', 'Products'], ['inventory', 'Inventory'], ['requisitions', 'Requisitions'], ['orders', 'Purchase Orders'], ['receipts', 'Goods Receipts'], ['invoices', 'Invoices & Payments'], ['reports', 'Reports'], ['ml', 'ML insights'], ['ask', 'Ask Data'], ['assistant', 'Procurement agent'], ['policy', 'Policy Q&A'], ['schema', 'Schema & ER']
];
export default function Layout({ page, setPage, user, onLogout, children }) {
  return <div className="shell"><aside className="sidebar"><div className="brand">Schema<span>Squad</span><small>Supply Chain Management</small></div><nav>{navigation.map(([key, label]) => <button key={key} className={page === key ? 'active' : ''} onClick={() => setPage(key)}>{label}</button>)}</nav><button className="logout" onClick={onLogout}>Sign out · {user.name}</button></aside><main>{children}</main></div>;
}
