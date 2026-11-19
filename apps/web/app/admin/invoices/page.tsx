'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { jakartaDate, rupiah, ui } from '@/lib/ui';

type Invoice = {
  id: string;
  number: string;
  distributor_id: string;
  total_commission: number;
  due_date: string;
  status: string;
  bank_reference: string | null;
};

export default function InvoicesPage() {
  return (
    <RoleGate role="admin">
      <AdminInvoices />
    </RoleGate>
  );
}

function AdminInvoices() {
  const [rows, setRows] = useState<Invoice[]>([]);
  const [overdue, setOverdue] = useState<number>(0);
  const [start, setStart] = useState(jakartaDate(-7));
  const [end, setEnd] = useState(jakartaDate(-1));
  const [refs, setRefs] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error } = await supabase
      .from('invoices')
      .select('id, number, distributor_id, total_commission, due_date, status, bank_reference')
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) setMessage({ ok: false, text: error.message });
    else setRows((data as Invoice[]) ?? []);

    const { data: od } = await supabase.rpc('overdue_invoices', { p_as_of: null });
    setOverdue(Array.isArray(od) ? od.length : 0);
  }

  useEffect(() => {
    load();
  }, []);

  async function generate() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error } = await supabase.rpc('generate_weekly_invoices', { p_period_start: start, p_period_end: end });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: `Faktur dibuat: ${data ?? 0}` });
    load();
  }

  async function markPaid(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('mark_invoice_paid', { p_invoice_id: id, p_bank_reference: refs[id] ?? '' });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Faktur ditandai dibayar.' });
    load();
  }

  return (
    <section style={ui.page}>
      <h1>Faktur komisi</h1>
      <div style={ui.card}>
        <strong>Buat faktur untuk pesanan yang dikonfirmasi</strong>
        <div style={ui.row}>
          <label>Dari <input type="date" style={ui.input} value={start} onChange={(e) => setStart(e.target.value)} /></label>
          <label>Sampai <input type="date" style={ui.input} value={end} onChange={(e) => setEnd(e.target.value)} /></label>
          <button style={ui.button} onClick={generate}>Buat faktur</button>
        </div>
      </div>
      <p style={overdue > 0 ? ui.error : ui.muted}>Faktur lewat jatuh tempo: {overdue}</p>
      {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      <table style={ui.table}>
        <thead>
          <tr>
            <th style={ui.th}>Nomor</th>
            <th style={{ ...ui.th, ...ui.right }}>Komisi</th>
            <th style={ui.th}>Jatuh tempo</th>
            <th style={ui.th}>Status</th>
            <th style={ui.th}>Tindakan</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((i) => (
            <tr key={i.id}>
              <td style={ui.td}>{i.number}</td>
              <td style={{ ...ui.td, ...ui.right }}>{rupiah(i.total_commission)}</td>
              <td style={ui.td}>{i.due_date}</td>
              <td style={ui.td}>{i.status === 'paid' ? `Dibayar (${i.bank_reference ?? ''})` : 'Belum dibayar'}</td>
              <td style={ui.td}>
                {i.status === 'unpaid' ? (
                  <div style={ui.row}>
                    <input
                      style={ui.input}
                      placeholder="Referensi mutasi"
                      value={refs[i.id] ?? ''}
                      onChange={(e) => setRefs({ ...refs, [i.id]: e.target.value })}
                    />
                    <button style={ui.buttonOutline} onClick={() => markPaid(i.id)}>Tandai dibayar</button>
                  </div>
                ) : (
                  <span style={ui.muted}>—</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
