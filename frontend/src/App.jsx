import { useState } from 'react';
import { auth, signIn } from './lib/api';
import Layout from './components/Layout';
import SqlPanel from './components/SqlPanel';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import DataPage from './pages/DataPage';
import Schema from './pages/Schema';
import MlInsights from './pages/MlInsights';
import AskData from './pages/AskData';
import Agent from './pages/Agent';
import PolicyQa from './pages/PolicyQa';

const config = {
  suppliers: ['Suppliers', 'Supplier directory and performance-ready master data.', '/suppliers', ['supplier_id','name','city','status','rating','email']],
  products: ['Products & categories', 'Product master, SKU catalogue and category classification.', '/products', ['product_id','sku','name','category_name','unit','std_cost']],
  inventory: ['Inventory', 'Stock by warehouse, including reorder thresholds.', '/inventory', ['warehouse_name','sku','product_name','qty_on_hand','reorder_level','reorder_qty']],
  requisitions: ['Requisitions', 'Create, approve and convert procurement demand into POs.', '/requisitions', ['req_id','requested_by_name','status','source','created_at']],
  orders: ['Purchase orders', 'Approved ordering workflow, supplier status and delivery progress.', '/orders', ['po_id','supplier_name','warehouse_name','order_date','status','total_amount','total_received_qty']],
  receipts: ['Goods receipts', 'Receive goods against approved purchase orders.', '/orders', ['po_id','supplier_name','status','total_ordered_qty','total_received_qty']],
  invoices: ['Invoices & payments', 'Three-way match state and outstanding payment balance.', '/invoices', ['invoice_id','invoice_no','supplier_name','due_date','invoice_amount','paid_amount','outstanding_amount','status']],
  reports: ['Reports', 'Spend by category and month.', '/reports/spend', ['month','category_name','spend','po_count']]
};
export default function App() {
  const [session, setSession] = useState(auth.get()); const [page, setPage] = useState('dashboard'); const [lastQuery, setLastQuery] = useState(null);
  if (!session) return <Login onLogin={async (email, password) => setSession(await signIn(email, password))} />;
  let content;
  if (page === 'dashboard') content = <Dashboard onQuery={setLastQuery} />;
  else if (page === 'ml') content = <MlInsights onQuery={setLastQuery} />;
  else if (page === 'ask') content = <AskData onQuery={setLastQuery} />;
  else if (page === 'assistant') content = <Agent onQuery={setLastQuery} />;
  else if (page === 'policy') content = <PolicyQa onQuery={setLastQuery} />;
  else if (page === 'schema') content = <Schema onQuery={setLastQuery} />;
  else { const [title, subtitle, endpoint, columns] = config[page]; content = <DataPage title={title} subtitle={subtitle} endpoint={endpoint} columns={columns} onQuery={setLastQuery} />; }
  return <Layout page={page} setPage={setPage} user={session.employee} onLogout={() => { auth.clear(); setSession(null); }}>{content}<SqlPanel lastQuery={lastQuery} /></Layout>;
}
