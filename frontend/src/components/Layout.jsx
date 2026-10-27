const navigation = [
  ['dashboard', 'Dashboard'], ['suppliers', 'Suppliers'], ['products', 'Products'], ['inventory', 'Inventory'], ['requisitions', 'Requisitions'], ['orders', 'Purchase Orders'], ['receipts', 'Goods Receipts'], ['invoices', 'Invoices & Payments'], ['reports', 'Reports'], ['ml', 'ML insights'], ['ask', 'Ask Data'], ['assistant', 'Procurement agent'], ['policy', 'Policy Q&A'], ['schema', 'Schema & ER']
];
export default function Layout({ page, setPage, user, onLogout, children }) {
  return <div className="shell"><aside className="sidebar"><div className="brand">Schema<span>Squad</span><small>Supply Chain Management</small></div><nav>{navigation.map(([key, label]) => <button key={key} className={page === key ? 'active' : ''} onClick={() => setPage(key)}>{label}</button>)}</nav><button className="logout" onClick={onLogout}>Sign out · {user.name}</button></aside><main>
      <header
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "flex-end",
          gap: "12px",
          padding: "12px 24px",
          background: "#ffffff",
          borderBottom: "1px solid #e2e8f0",
          position: "sticky",
          top: 0,
          zIndex: 20
        }}
      >
        <span style={{ color: "#475569", fontSize: "14px" }}>
          Signed in as <strong>{user?.name || user?.email || "User"}</strong>
        </span>

        <button
          type="button"
          onClick={onLogout}
          style={{
            border: "none",
            borderRadius: "8px",
            padding: "9px 16px",
            background: "#b91c1c",
            color: "#ffffff",
            fontWeight: 600,
            cursor: "pointer"
          }}
        >
          Log out
        </button>
      </header>

      {children}
    </main></div>;
}
