'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { rupiah, ui } from '@/lib/ui';

type Invoice = { id: string; number: string; total_commission: number; due_date: string; status: string; paid_at: string | null };

export default function DistributorInvoicesPage() {
  return (
    <RoleGate role="distributor">
      <Invoices />
    </RoleGate>
  );
}

function Invoices() {
  const [rows, setRows] = useState<Invoice[]>([]);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) return;
    supabase
      .from('invoices')
      .select('id, number, total_commission, due_date, status, paid_at')
      .order('created_at', { ascending: false })
      .then(({ data, error }) => {
        if (error) setMessage(error.message);
        else setRows((data as Invoice[]) ?? []);
      });
  }, []);

  return (
    <section style={ui.page}>
      <h1>Faktur komisi</h1>
      <p style={ui.muted}>Komisi dibayar ke rekening MitraLink melalui transfer, sesuai nomor faktur.</p>
      {message ? <p style={ui.error}>{message}</p> : null}
      <table style={ui.table}>
        <thead>
          <tr>
            <th style={ui.th}>Nomor</th>
            <th style={{ ...ui.th, ...ui.right }}>Komisi</th>
            <th style={ui.th}>Jatuh tempo</th>
            <th style={ui.th}>Status</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((i) => (
            <tr key={i.id}>
              <td style={ui.td}>{i.number}</td>
              <td style={{ ...ui.td, ...ui.right }}>{rupiah(i.total_commission)}</td>
              <td style={ui.td}>{i.due_date}</td>
              <td style={ui.td}>{i.status === 'paid' ? 'Dibayar' : 'Belum dibayar'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
