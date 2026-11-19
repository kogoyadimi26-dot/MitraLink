'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { newClientId, rupiah, ui } from '@/lib/ui';

type OrderRow = { id: string; code: string; state: string; subtotal: number; created_at: string };

export default function OrdersPage() {
  return (
    <RoleGate role="admin">
      <AdminOrders />
    </RoleGate>
  );
}

function AdminOrders() {
  const [rows, setRows] = useState<OrderRow[]>([]);
  const [stateFilter, setStateFilter] = useState('');
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    let q = supabase.from('orders').select('id, code, state, subtotal, created_at').order('created_at', { ascending: false }).limit(100);
    if (stateFilter) q = q.eq('state', stateFilter);
    const { data, error } = await q;
    if (error) setMessage({ ok: false, text: error.message });
    else setRows((data as OrderRow[]) ?? []);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stateFilter]);

  async function cancel(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('transition_order', {
      p_order_id: id, p_to: 'Cancelled', p_client_id: newClientId(), p_reference: null, p_note: reasons[id] ?? '',
    });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Pesanan dibatalkan.' });
    load();
  }

  async function reversePayment(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('admin_reverse_payment', { p_order_id: id, p_reason: reasons[id] ?? '' });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Pembayaran dibatalkan. Pesanan kembali menunggu pembayaran.' });
    load();
  }

  return (
    <section style={ui.page}>
      <h1>Pesanan</h1>
      <div style={ui.row}>
        <label>
          Status{' '}
          <select style={ui.input} value={stateFilter} onChange={(e) => setStateFilter(e.target.value)}>
            <option value="">Semua</option>
            {['Placed', 'AwaitingPayment', 'Paid', 'Shipped', 'Confirmed', 'Disputed', 'Cancelled', 'Declined'].map((s) => (
              <option key={s} value={s}>{s}</option>
            ))}
          </select>
        </label>
      </div>
      {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      <table style={ui.table}>
        <thead>
          <tr>
            <th style={ui.th}>Kode</th>
            <th style={ui.th}>Status</th>
            <th style={{ ...ui.th, ...ui.right }}>Total</th>
            <th style={ui.th}>Tindakan</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((o) => (
            <tr key={o.id}>
              <td style={ui.td}>{o.code}</td>
              <td style={ui.td}>{o.state}</td>
              <td style={{ ...ui.td, ...ui.right }}>{rupiah(o.subtotal)}</td>
              <td style={ui.td}>
                {o.state === 'AwaitingPayment' || o.state === 'Paid' ? (
                  <div style={ui.row}>
                    <input
                      style={ui.input}
                      placeholder="Alasan"
                      value={reasons[o.id] ?? ''}
                      onChange={(e) => setReasons({ ...reasons, [o.id]: e.target.value })}
                    />
                    {o.state === 'AwaitingPayment' ? (
                      <button style={ui.buttonOutline} onClick={() => cancel(o.id)}>Batalkan</button>
                    ) : (
                      <button style={ui.buttonOutline} onClick={() => reversePayment(o.id)}>Batalkan pembayaran</button>
                    )}
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
