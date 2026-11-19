'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { ui } from '@/lib/ui';

type Pending = { id: string; business_name: string; created_at: string };

export default function ApprovalsPage() {
  return (
    <RoleGate role="admin">
      <Approvals />
    </RoleGate>
  );
}

function Approvals() {
  const [rows, setRows] = useState<Pending[]>([]);
  const [terms, setTerms] = useState('v1');
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error } = await supabase
      .from('distributors')
      .select('id, business_name, created_at')
      .eq('approval_status', 'pending')
      .order('created_at', { ascending: true });
    if (error) setMessage({ ok: false, text: error.message });
    else setRows((data as Pending[]) ?? []);
  }

  useEffect(() => {
    load();
  }, []);

  async function approve(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('approve_distributor', { p_distributor_id: id, p_commission_terms_version: terms });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Distributor disetujui.' });
    load();
  }

  async function reject(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('reject_distributor', { p_distributor_id: id, p_reason: reasons[id] ?? '' });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Distributor ditolak.' });
    load();
  }

  return (
    <section style={ui.page}>
      <h1>Persetujuan distributor</h1>
      <div style={ui.row}>
        <label>
          Versi ketentuan komisi:{' '}
          <input style={ui.input} value={terms} onChange={(e) => setTerms(e.target.value)} />
        </label>
      </div>
      {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      {rows.length === 0 ? <p style={ui.muted}>Tidak ada distributor yang menunggu.</p> : null}
      {rows.map((d) => (
        <div key={d.id} style={ui.card}>
          <strong>{d.business_name}</strong>
          <span style={ui.muted}>Mendaftar {new Date(d.created_at).toLocaleDateString('id-ID')}</span>
          <div style={ui.row}>
            <button style={ui.button} onClick={() => approve(d.id)}>Setujui</button>
            <input
              style={ui.input}
              placeholder="Alasan penolakan"
              value={reasons[d.id] ?? ''}
              onChange={(e) => setReasons({ ...reasons, [d.id]: e.target.value })}
            />
            <button style={ui.buttonOutline} onClick={() => reject(d.id)}>Tolak</button>
          </div>
        </div>
      ))}
    </section>
  );
}
