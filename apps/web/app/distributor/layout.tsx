import Link from 'next/link';

export default function DistributorLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <header className="topbar">
        <Link href="/distributor" className="brand">
          <span className="brand-mark" aria-hidden>M</span>
          MitraLink
        </Link>
        <nav className="nav" aria-label="Menu distributor">
          <Link href="/distributor/products">Produk</Link>
          <Link href="/distributor/orders">Pesanan</Link>
          <Link href="/distributor/invoices">Faktur</Link>
        </nav>
      </header>
      {children}
    </>
  );
}
