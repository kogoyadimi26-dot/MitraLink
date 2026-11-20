import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'MitraLink',
  description: 'Papua Distribution Connect: distributor and admin dashboard',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="id">
      <body>
        <main className="app-main">{children}</main>
      </body>
    </html>
  );
}
