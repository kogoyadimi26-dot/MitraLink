'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { ui } from '@/lib/ui';

type AuditRow = { id: number; created_at: string; actor_role: string; action: string; entity: string; entity_id: string };

export default function AuditPage() {
  return (
    <RoleGate role="admin">
      <Audit />
    </RoleGate>
  );
}

function Audit() {
  const [entity, setEntity] = useState('');
  const [entityId, setEntityId] = useState('');
  const [action, setAction] = useState('');
  const [rows, setRows] = useState<AuditRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  async function search() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error: rpcError } = await supabase.rpc('admin_search_audit', {
      p_entity: entity || null,
      p_entity_id: entityId || null,
      p_action: action || null,
      p_from: null,
      p_to: null,
      p_limit: 100,
    });
    if (rpcError) {
      setError(rpcError.message);
      setRows([]);
    } else {
      setError(null);
      setRows((data as AuditRow[]) ?? []);
    }
  }

  useEffect(() => {
    search();
    // Shows the latest entries on open.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <section style={ui.page}>
      <h1>Catatan audit</h1>
      <div style={ui.row}>
        <input style={ui.input} placeholder="Jenis (order, invoice, distributor...)" value={entity} onChange={(e) => setEntity(e.target.value)} />
        <input style={ui.input} placeholder="ID data" value={entityId} onChange={(e) => setEntityId(e.target.value)} />
        <input style={ui.input} placeholder="Tindakan" value={action} onChange={(e) => setAction(e.target.value)} />
        <button style={ui.button} onClick={search}>Cari</button>
      </div>
      {error ? <p style={ui.error}>{error}</p> : null}
      <table style={ui.table}>
        <thead>
          <tr>
            <th style={ui.th}>Waktu</th>
            <th style={ui.th}>Oleh</th>
            <th style={ui.th}>Tindakan</th>
            <th style={ui.th}>Jenis</th>
            <th style={ui.th}>ID</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td style={ui.td}>{new Date(r.created_at).toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })}</td>
              <td style={ui.td}>{r.actor_role}</td>
              <td style={ui.td}>{r.action}</td>
              <td style={ui.td}>{r.entity}</td>
              <td style={ui.td}>{r.entity_id}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
