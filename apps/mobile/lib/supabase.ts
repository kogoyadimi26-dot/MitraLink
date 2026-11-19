import 'react-native-url-polyfill/auto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Client for the dev project. Values come from EXPO_PUBLIC_* variables (see .env.example).
 * Returns null when they are not set, so the screens can say so. Sessions are not persisted yet:
 * sign-in waits for the SMS provider decision (D-001).
 */
export function getSupabase(): SupabaseClient | null {
  const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
  const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
