'use client';

import Link from 'next/link';
import RoleGate from '@/components/RoleGate';
import { ui } from '@/lib/ui';

export default function DistributorHome() {
  return (
    <RoleGate role="distributor">
      <section style={ui.page}>
        <h1>Distributor</h1>
        <ul>
          <li><Link href="/distributor/orders">Pesanan masuk</Link></li>
          <li><Link href="/distributor/products">Produk saya</Link></li>
          <li><Link href="/distributor/invoices">Faktur komisi</Link></li>
        </ul>
      </section>
    </RoleGate>
  );
}
