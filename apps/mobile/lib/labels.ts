import { formatRupiah } from '@mitralink/shared';

/** Bahasa Indonesia labels for order states, as the buyer sees them. */
export const STATE_LABEL: Record<string, string> = {
  Placed: 'Menunggu distributor',
  Accepted: 'Diterima distributor',
  Declined: 'Ditolak distributor',
  AwaitingPayment: 'Menunggu pembayaran',
  Paid: 'Pembayaran diterima',
  Shipped: 'Dikirim',
  Confirmed: 'Selesai',
  Disputed: 'Ada masalah',
  Cancelled: 'Dibatalkan',
};

export function money(amount: number): string {
  return formatRupiah(amount);
}
