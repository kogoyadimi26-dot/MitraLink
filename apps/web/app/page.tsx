import Link from 'next/link';

export default function Home() {
  return (
    <section>
      <h1>MitraLink</h1>
      <p>Dashboard untuk admin dan distributor.</p>
      <ul>
        <li>
          <Link href="/admin/kpi">Laporan KPI (admin)</Link>
        </li>
        <li>
          <Link href="/admin/approvals">Persetujuan distributor (admin)</Link>
        </li>
      </ul>
      <p style={{ color: '#5d6661', fontSize: 14 }}>
        Masuk belum tersedia. Menunggu keputusan penyedia SMS (D-001).
      </p>
    </section>
  );
}
