import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * Browser-safe client for the dev project. Values come from the environment (see .env.example).
 * Returns null when they are not set, so pages can say so instead of failing.
 */
export function getSupabase(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key);
}
