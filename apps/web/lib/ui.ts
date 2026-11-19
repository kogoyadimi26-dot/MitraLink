import type { CSSProperties } from 'react';

export const ui = {
  page: { display: 'grid', gap: 16 } satisfies CSSProperties,
  card: { background: '#ffffff', border: '1px solid #dcd8cc', borderRadius: 10, padding: 16, display: 'grid', gap: 10 } satisfies CSSProperties,
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 14 } satisfies CSSProperties,
  th: { textAlign: 'left', padding: '8px 6px', borderBottom: '1px solid #dcd8cc', color: '#5d6661', fontWeight: 600 } satisfies CSSProperties,
  td: { padding: '8px 6px', borderBottom: '1px solid #eee', verticalAlign: 'top' } satisfies CSSProperties,
  right: { textAlign: 'right' } satisfies CSSProperties,
  input: { padding: 8, borderRadius: 6, border: '1px solid #dcd8cc', font: 'inherit' } satisfies CSSProperties,
  button: { padding: '8px 12px', borderRadius: 6, border: '1px solid #2c6b4f', background: '#2c6b4f', color: '#ffffff', cursor: 'pointer', font: 'inherit' } satisfies CSSProperties,
  buttonOutline: { padding: '8px 12px', borderRadius: 6, border: '1px solid #2c6b4f', background: 'transparent', color: '#2c6b4f', cursor: 'pointer', font: 'inherit' } satisfies CSSProperties,
  muted: { color: '#5d6661', fontSize: 13 } satisfies CSSProperties,
  error: { color: '#9b3d2e', fontSize: 14 } satisfies CSSProperties,
  ok: { color: '#2c6b4f', fontSize: 14 } satisfies CSSProperties,
  row: { display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' } satisfies CSSProperties,
};

/** Rupiah for display, e.g. 1000000 becomes "Rp1.000.000". */
export function rupiah(amount: number | null | undefined): string {
  if (amount === null || amount === undefined) return '—';
  return 'Rp' + Math.round(amount).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/** Today's date in Indonesian time, offset by a number of days. */
export function jakartaDate(offsetDays: number): string {
  const d = new Date(Date.now() + offsetDays * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(d);
}

/** A random version 4 UUID, used as the client id for retries. */
export function newClientId(): string {
  return crypto.randomUUID();
}
