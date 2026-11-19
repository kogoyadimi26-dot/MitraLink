import { formatRupiah } from '@mitralink/shared';
import { getSupabase } from '@/lib/supabase';

type KpiRow = { metric: string; value: number | null; target: number | null; unit: string };

const LABELS: Record<string, string> = {
  distributors_approved: 'Distributor disetujui',
  buyers_ordering: 'Pembeli yang memesan',
  orders_per_week: 'Pesanan per minggu',
  orders_confirmed: 'Pesanan dikonfirmasi',
  on_time_confirmation_pct: 'Konfirmasi tepat waktu (%)',
  dispute_rate_pct: 'Tingkat sengketa (%)',
  invoices_paid_on_time_pct: 'Faktur dibayar tepat waktu (%)',
};

function jakartaDate(offsetDays: number): string {
  const d = new Date(Date.now() + offsetDays * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(d);
}

export default async function KpiPage() {
  const supabase = getSupabase();
  if (!supabase) {
    return <p>Konfigurasi Supabase belum diisi (lihat .env.example).</p>;
  }

  const from = jakartaDate(-6);
  const to = jakartaDate(0);
  const { data, error } = await supabase.rpc('kpi_report', { p_from: from, p_to: to });

  return (
    <section>
      <h1>Laporan KPI</h1>
      <p>Periode {from} sampai {to} (WIB). Menampilkan data hanya setelah admin masuk.</p>
      {error ? (
        <p style={{ color: '#9b3d2e' }}>Tidak dapat memuat: {error.message}</p>
      ) : (
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left' }}>Metrik</th>
              <th style={{ textAlign: 'right' }}>Nilai</th>
              <th style={{ textAlign: 'right' }}>Target</th>
            </tr>
          </thead>
          <tbody>
            {(data as KpiRow[] | null)?.map((row) => (
              <tr key={row.metric}>
                <td>{LABELS[row.metric] ?? row.metric}</td>
                <td style={{ textAlign: 'right' }}>{row.value ?? '—'}</td>
                <td style={{ textAlign: 'right' }}>{row.target ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p style={{ color: '#5d6661', fontSize: 13 }}>
        Contoh tampilan rupiah: {formatRupiah(25000)}.
      </p>
    </section>
  );
}
