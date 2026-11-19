'use client';

import { useEffect, useState } from 'react';
import { normalizeIndonesianPhone } from '@mitralink/shared';
import { getSupabase } from '@/lib/supabase';
import { ui } from '@/lib/ui';
import RegisterDistributor from '@/components/RegisterDistributor';

/**
 * Sign-in with a one-time code sent by SMS. The SMS provider must be set up in the Supabase
 * project first (decision D-001). The session is kept in this browser.
 */
export default function MasukPage() {
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [phoneInput, setPhoneInput] = useState('');
  const [phone, setPhone] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [signedInAs, setSignedInAs] = useState<string | null>(null);
  // null = not checked yet; false = signed in but no profile (needs registration); true = has a profile.
  const [hasProfile, setHasProfile] = useState<boolean | null>(null);

  async function checkProfile(userId: string | null) {
    const supabase = getSupabase();
    if (!supabase || !userId) {
      setHasProfile(null);
      return;
    }
    const { data } = await supabase.from('profiles').select('id').eq('id', userId).maybeSingle();
    setHasProfile(!!data);
  }

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => {
      const uid = data.session?.user.id ?? null;
      setSignedInAs(uid);
      checkProfile(uid);
    });
    // checkProfile reads the database only; it is run once when the page opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function requestCode() {
    const supabase = getSupabase();
    if (!supabase) {
      setMessage({ ok: false, text: 'Konfigurasi Supabase belum diisi (lihat .env.example).' });
      return;
    }
    const normalized = normalizeIndonesianPhone(phoneInput);
    if (!normalized) {
      setMessage({ ok: false, text: 'Nomor HP tidak valid. Contoh: 0812 3456 7890.' });
      return;
    }
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.auth.signInWithOtp({ phone: normalized });
    setBusy(false);
    if (error) {
      setMessage({ ok: false, text: error.message });
      return;
    }
    setPhone(normalized);
    setStep('code');
  }

  async function checkCode() {
    const supabase = getSupabase();
    if (!supabase || !phone) return;
    setBusy(true);
    setMessage(null);
    const { data, error } = await supabase.auth.verifyOtp({ phone, token: code.trim(), type: 'sms' });
    setBusy(false);
    if (error) {
      setMessage({ ok: false, text: 'Kode salah atau sudah kedaluwarsa. Coba lagi.' });
      return;
    }
    const uid = data.session?.user.id ?? null;
    setSignedInAs(uid);
    setMessage({ ok: true, text: 'Anda sudah masuk.' });
    checkProfile(uid);
  }

  async function signOut() {
    const supabase = getSupabase();
    if (supabase) await supabase.auth.signOut();
    setSignedInAs(null);
    setHasProfile(null);
    setStep('phone');
    setCode('');
    setMessage({ ok: true, text: 'Anda sudah keluar.' });
  }

  if (signedInAs && hasProfile === false) {
    return (
      <section style={ui.page}>
        <RegisterDistributor onRegistered={() => checkProfile(signedInAs)} />
        <button style={ui.buttonOutline} onClick={signOut}>Keluar</button>
      </section>
    );
  }

  if (signedInAs) {
    return (
      <section style={ui.page}>
        <h1>Masuk</h1>
        <p style={ui.ok}>Anda sudah masuk.</p>
        <div style={ui.row}>
          <a href="/admin">Admin</a>
          <a href="/distributor">Distributor</a>
        </div>
        <button style={ui.buttonOutline} onClick={signOut}>Keluar</button>
        {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      </section>
    );
  }

  return (
    <section style={ui.page}>
      <h1>Masuk</h1>
      {step === 'phone' ? (
        <div style={ui.card}>
          <p>Masukkan nomor HP. Kode akan dikirim lewat SMS.</p>
          <div style={ui.row}>
            <input style={ui.input} placeholder="0812 3456 7890" inputMode="tel" value={phoneInput} onChange={(e) => setPhoneInput(e.target.value)} />
            <button style={ui.button} onClick={requestCode} disabled={busy}>Kirim kode</button>
          </div>
        </div>
      ) : (
        <div style={ui.card}>
          <p>Masukkan kode yang dikirim ke {phone}.</p>
          <div style={ui.row}>
            <input style={ui.input} placeholder="Kode dari SMS" inputMode="numeric" value={code} onChange={(e) => setCode(e.target.value)} />
            <button style={ui.button} onClick={checkCode} disabled={busy}>Masuk</button>
            <button style={ui.buttonOutline} onClick={() => setStep('phone')}>Ganti nomor</button>
          </div>
        </div>
      )}
      {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
    </section>
  );
}
