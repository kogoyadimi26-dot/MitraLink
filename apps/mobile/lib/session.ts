import { normalizeIndonesianPhone } from '@mitralink/shared';
import { getSupabase } from './supabase';

/** The signed-in user's id, or null. */
export async function currentUserId(): Promise<string | null> {
  const supabase = getSupabase();
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session?.user.id ?? null;
}

/**
 * Sends a one-time code by SMS. The SMS provider must be set up in the Supabase project first
 * (decision D-001). Returns an error message, or null when the code was sent.
 */
export async function sendCode(phoneInput: string): Promise<{ phone: string | null; error: string | null }> {
  const phone = normalizeIndonesianPhone(phoneInput);
  if (!phone) return { phone: null, error: 'Nomor HP tidak valid. Contoh: 0812 3456 7890.' };
  const supabase = getSupabase();
  if (!supabase) return { phone, error: 'Konfigurasi Supabase belum diisi (lihat .env.example).' };
  const { error } = await supabase.auth.signInWithOtp({ phone });
  return { phone, error: error ? error.message : null };
}

/** Checks the code. Returns an error message, or null when the user is signed in. */
export async function verifyCode(phone: string, code: string): Promise<string | null> {
  const supabase = getSupabase();
  if (!supabase) return 'Konfigurasi Supabase belum diisi (lihat .env.example).';
  const { error } = await supabase.auth.verifyOtp({ phone, token: code.trim(), type: 'sms' });
  return error ? 'Kode salah atau sudah kedaluwarsa. Coba lagi.' : null;
}

export async function signOut(): Promise<void> {
  const supabase = getSupabase();
  if (supabase) await supabase.auth.signOut();
}
