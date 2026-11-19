import Link from 'next/link';
import { ui } from '@/lib/ui';

export default function AdminHome() {
  return (
    <section style={ui.page}>
      <h1>Admin</h1>
      <ul>
        <li><Link href="/admin/kpi">Laporan KPI</Link></li>
        <li><Link href="/admin/approvals">Persetujuan distributor</Link></li>
        <li><Link href="/admin/orders">Pesanan</Link></li>
        <li><Link href="/admin/invoices">Faktur komisi</Link></li>
        <li><Link href="/admin/audit">Catatan audit</Link></li>
      </ul>
    </section>
  );
}
