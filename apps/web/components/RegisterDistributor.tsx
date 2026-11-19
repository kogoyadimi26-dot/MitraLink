'use client';

import { useState } from 'react';
import { normalizeIndonesianPhone } from '@mitralink/shared';
import { getSupabase } from '@/lib/supabase';
import { ui } from '@/lib/ui';

/** Terms version accepted at registration (FR-02). The terms are still a draft. */
export const TERMS_VERSION = 'v1';

const TOWNS = [
  { code: 'J', label: 'Jayapura' },
  { code: 'W', label: 'Wamena' },
];

/**
 * First-time registration for a distributor after sign-in (FR-03). The account starts pending
 * until admin approves it. The database checks everything else.
 */
export default function RegisterDistributor({ onRegistered }: { onRegistered: () => void }) {
  const [form, setForm] = useState({
    fullName: '',
    businessName: '',
    town: 'J',
    taxNumber: '',
    bankName: '',
    bankAccount: '',
  });
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  function set(field: keyof typeof form, value: string) {
    setForm({ ...form, [field]: value });
  }

  async function submit() {
    setMessage(null);
    if (!form.fullName.trim() || !form.businessName.trim() || !form.bankName.trim() || !form.bankAccount.trim()) {
      setMessage({ ok: false, text: 'Isi nama, nama usaha, bank, dan nomor rekening.' });
      return;
    }
    if (!accepted) {
      setMessage({ ok: false, text: 'Setujui syarat dan ketentuan untuk mendaftar.' });
      return;
    }
    const supabase = getSupabase();
    if (!supabase) {
      setMessage({ ok: false, text: 'Konfigurasi Supabase belum diisi (lihat .env.example).' });
      return;
    }
    const { data: session } = await supabase.auth.getSession();
    const userId = session.session?.user.id;
    // Supabase stores the number without the leading +; the database needs +62 (profiles.phone).
    const phone = normalizeIndonesianPhone(session.session?.user.phone ?? '');
    if (!userId || !phone) {
      setMessage({ ok: false, text: 'Masuk dulu dengan nomor HP.' });
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc('register_distributor', {
      p_user_id: userId,
      p_phone: phone,
      p_full_name: form.fullName.trim(),
      p_business_name: form.businessName.trim(),
      p_town_code: form.town,
      p_tax_number: form.taxNumber.trim() || null,
      p_bank_name: form.bankName.trim(),
      p_bank_account: form.bankAccount.trim(),
      p_terms_version: TERMS_VERSION,
    });
    setBusy(false);
    if (error) {
      setMessage({ ok: false, text: error.message });
      return;
    }
    onRegistered();
  }

  return (
    <section style={ui.page}>
      <h1>Daftar distributor</h1>
      <p style={ui.muted}>Akun baru menunggu persetujuan admin sebelum bisa menerima pesanan.</p>
      <div style={ui.card}>
        <label>Nama Anda <input style={ui.input} value={form.fullName} onChange={(e) => set('fullName', e.target.value)} /></label>
        <label>Nama usaha <input style={ui.input} value={form.businessName} onChange={(e) => set('businessName', e.target.value)} /></label>
        <label>
          Kota{' '}
          <select style={ui.input} value={form.town} onChange={(e) => set('town', e.target.value)}>
            {TOWNS.map((t) => (
              <option key={t.code} value={t.code}>{t.label}</option>
            ))}
          </select>
        </label>
        <label>NPWP (opsional) <input style={ui.input} value={form.taxNumber} onChange={(e) => set('taxNumber', e.target.value)} /></label>
        <label>Nama bank <input style={ui.input} value={form.bankName} onChange={(e) => set('bankName', e.target.value)} /></label>
        <label>Nomor rekening <input style={ui.input} value={form.bankAccount} onChange={(e) => set('bankAccount', e.target.value)} /></label>
        <label>
          <input type="checkbox" checked={accepted} onChange={(e) => setAccepted(e.target.checked)} />{' '}
          Saya setuju dengan syarat dan ketentuan MitraLink (versi {TERMS_VERSION}).
        </label>
        <div style={ui.row}>
          <button style={ui.button} onClick={submit} disabled={busy}>{busy ? 'Mengirim...' : 'Daftar'}</button>
        </div>
        {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      </div>
    </section>
  );
}
