import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'MitraLink',
  description: 'Papua Distribution Connect: distributor and admin dashboard',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <body style={{ margin: 0, fontFamily: 'system-ui, sans-serif', color: '#1d2623', background: '#f6f4ee' }}>
        <main style={{ maxWidth: 960, margin: '0 auto', padding: '32px 16px 64px' }}>{children}</main>
      </body>
    </html>
  );
}
