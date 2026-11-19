'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { newClientId, rupiah, ui } from '@/lib/ui';

type OrderRow = { id: string; code: string; state: string; subtotal: number; created_at: string };

export default function DistributorOrdersPage() {
  return (
    <RoleGate role="distributor">
      <Orders />
    </RoleGate>
  );
}

const STATE_TEXT: Record<string, string> = {
  Placed: 'Baru, perlu diterima atau ditolak',
  AwaitingPayment: 'Menunggu pembayaran dari pembeli',
  Paid: 'Sudah dibayar, siap dikirim',
  Shipped: 'Dikirim, menunggu konfirmasi pembeli',
  Confirmed: 'Selesai',
  Disputed: 'Ada masalah, ditangani admin',
  Declined: 'Ditolak',
  Cancelled: 'Dibatalkan',
};

function Orders() {
  const [rows, setRows] = useState<OrderRow[]>([]);
  const [refs, setRefs] = useState<Record<string, string>>({});
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error } = await supabase
      .from('orders')
      .select('id, code, state, subtotal, created_at')
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) setMessage({ ok: false, text: error.message });
    else setRows((data as OrderRow[]) ?? []);
  }

  useEffect(() => {
    load();
  }, []);

  // Every step goes through transition_order. The client id makes a retry safe.
  async function step(id: string, to: string, reference: string | null, note: string | null) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('transition_order', {
      p_order_id: id, p_to: to, p_client_id: newClientId(), p_reference: reference, p_note: note,
    });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Status diperbarui.' });
    load();
  }

  return (
    <section style={ui.page}>
      <h1>Pesanan masuk</h1>
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
              <td style={ui.td}>{STATE_TEXT[o.state] ?? o.state}</td>
              <td style={{ ...ui.td, ...ui.right }}>{rupiah(o.subtotal)}</td>
              <td style={ui.td}>
                {o.state === 'Placed' ? (
                  <div style={ui.row}>
                    <button style={ui.button} onClick={() => step(o.id, 'Accepted', null, null)}>Terima</button>
                    <input style={ui.input} placeholder="Alasan tolak" value={reasons[o.id] ?? ''} onChange={(e) => setReasons({ ...reasons, [o.id]: e.target.value })} />
                    <button style={ui.buttonOutline} onClick={() => step(o.id, 'Declined', null, reasons[o.id] ?? '')}>Tolak</button>
                  </div>
                ) : null}
                {o.state === 'AwaitingPayment' ? (
                  <div style={ui.row}>
                    <input style={ui.input} placeholder="Kode di mutasi bank" value={refs[o.id] ?? ''} onChange={(e) => setRefs({ ...refs, [o.id]: e.target.value })} />
                    <button style={ui.button} onClick={() => step(o.id, 'Paid', refs[o.id] ?? '', null)} disabled={!refs[o.id]}>Sudah dibayar</button>
                  </div>
                ) : null}
                {o.state === 'Paid' ? (
                  <button style={ui.button} onClick={() => step(o.id, 'Shipped', null, null)}>Tandai dikirim</button>
                ) : null}
                {!['Placed', 'AwaitingPayment', 'Paid'].includes(o.state) ? <span style={ui.muted}>—</span> : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <p style={ui.muted}>Tandai sudah dibayar hanya setelah transfer terlihat di rekening Anda (BR-05).</p>
    </section>
  );
}
