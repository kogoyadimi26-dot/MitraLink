'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { jakartaDate, ui } from '@/lib/ui';

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

export default function KpiPage() {
  return (
    <RoleGate role="admin">
      <Kpi />
    </RoleGate>
  );
}

function Kpi() {
  const [from, setFrom] = useState(jakartaDate(-6));
  const [to, setTo] = useState(jakartaDate(0));
  const [rows, setRows] = useState<KpiRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error: rpcError } = await supabase.rpc('kpi_report', { p_from: from, p_to: to });
    if (rpcError) {
      setError(rpcError.message);
      setRows(null);
    } else {
      setError(null);
      setRows((data as KpiRow[]) ?? []);
    }
  }

  useEffect(() => {
    load();
    // Loads once for the default period; the button reloads for the chosen one.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <section style={ui.page}>
      <h1>Laporan KPI</h1>
      <div style={ui.row}>
        <label>Dari <input type="date" style={ui.input} value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label>Sampai <input type="date" style={ui.input} value={to} onChange={(e) => setTo(e.target.value)} /></label>
        <button style={ui.button} onClick={load}>Tampilkan</button>
      </div>
      {error ? <p style={ui.error}>{error}</p> : null}
      {rows ? (
        <table style={ui.table}>
          <thead>
            <tr>
              <th style={ui.th}>Metrik</th>
              <th style={{ ...ui.th, ...ui.right }}>Nilai</th>
              <th style={{ ...ui.th, ...ui.right }}>Target</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.metric}>
                <td style={ui.td}>{LABELS[r.metric] ?? r.metric}</td>
                <td style={{ ...ui.td, ...ui.right }}>{r.value ?? '—'}</td>
                <td style={{ ...ui.td, ...ui.right }}>{r.target ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </section>
  );
}
