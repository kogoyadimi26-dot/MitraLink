import Link from 'next/link';
import { ui } from '@/lib/ui';

export default function Home() {
  return (
    <section style={ui.page}>
      <h1>MitraLink</h1>
      <p>Dashboard untuk admin dan distributor.</p>
      <ul>
        <li><Link href="/admin">Admin</Link></li>
        <li><Link href="/distributor">Distributor</Link></li>
        <li><Link href="/masuk">Masuk</Link></li>
      </ul>
    </section>
  );
}
