'use client';

import { useEffect, useState, type ReactNode } from 'react';
import { getSupabase } from '@/lib/supabase';
import { ui } from '@/lib/ui';

type Role = 'admin' | 'distributor';
type Status = 'checking' | 'ok' | 'signin' | 'noprofile' | 'wrongrole' | 'unconfigured';

/**
 * Shows its children only to a signed-in, active user with the given role. Access is still enforced
 * by the database: this only decides what to show.
 */
export default function RoleGate({ role, children }: { role: Role; children: ReactNode }) {
  const [status, setStatus] = useState<Status>('checking');

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) {
      setStatus('unconfigured');
      return;
    }
    (async () => {
      const { data: session } = await supabase.auth.getSession();
      const uid = session.session?.user.id;
      if (!uid) {
        setStatus('signin');
        return;
      }
      const { data: profile } = await supabase.from('profiles').select('role, status').eq('id', uid).maybeSingle();
      if (!profile) {
        setStatus('noprofile');
        return;
      }
      if (profile.role !== role || profile.status !== 'active') {
        setStatus('wrongrole');
        return;
      }
      setStatus('ok');
    })();
  }, [role]);

  if (status === 'checking') return <p style={ui.muted}>Memuat...</p>;
  if (status === 'unconfigured') return <p style={ui.error}>Konfigurasi Supabase belum diisi (lihat .env.example).</p>;
  if (status === 'signin') {
    return (
      <p style={ui.error}>
        Masuk diperlukan. <a href="/masuk">Masuk dengan nomor HP</a>.
      </p>
    );
  }
  if (status === 'noprofile') {
    return (
      <p style={ui.error}>
        Akun belum terdaftar. <a href="/masuk">Lanjutkan pendaftaran di halaman Masuk</a>.
      </p>
    );
  }
  if (status === 'wrongrole') {
    return <p style={ui.error}>Akun ini tidak punya akses ke halaman ini.</p>;
  }
  return <>{children}</>;
}
