import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { getSupabase } from '../lib/supabase';
import { STATE_LABEL, money } from '../lib/labels';
import { newClientId } from '../lib/cart';

type Order = { id: string; code: string; state: string; subtotal: number };
type PaymentInfo = { bank_name: string; bank_account: string; distributor_name: string; amount: number };

type Props = { orderId: string; onBack: () => void; onChanged: () => void };

export default function OrderDetail({ orderId, onBack, onChanged }: Props) {
  const [order, setOrder] = useState<Order | null>(null);
  const [payment, setPayment] = useState<PaymentInfo | null>(null);
  const [reason, setReason] = useState('');
  const [showDispute, setShowDispute] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) {
      setMessage('Konfigurasi Supabase belum diisi (lihat .env.example).');
      return;
    }
    const { data } = await supabase
      .from('orders')
      .select('id, code, state, subtotal')
      .eq('id', orderId)
      .maybeSingle();
    setOrder((data as Order | null) ?? null);

    if (data && ((data as Order).state === 'AwaitingPayment' || (data as Order).state === 'Paid')) {
      // Bank details are returned only to the buyer or agent of this order, and only while payment is due or received.
      const { data: info, error } = await supabase.rpc('get_payment_instructions', { p_order_id: orderId });
      if (!error && Array.isArray(info) && info[0]) {
        const row = info[0] as { bank_name: string; bank_account: string; distributor_name: string; amount: number };
        setPayment(row);
      }
    } else {
      setPayment(null);
    }
  }

  useEffect(() => {
    load();
    // load is re-run when the order id changes; it reads only the given order.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orderId]);

  // The buyer confirms receipt. The client id makes a retry safe.
  async function confirmReceipt() {
    await runTransition('Confirmed', null, null);
  }

  async function raiseDispute() {
    if (reason.trim().length === 0) {
      setMessage('Tulis alasan masalah dengan singkat.');
      return;
    }
    await runTransition('Disputed', null, reason.trim());
  }

  async function runTransition(to: string, reference: string | null, note: string | null) {
    const supabase = getSupabase();
    if (!supabase) return;
    setBusy(true);
    setMessage(null);
    const { data, error } = await supabase.rpc('transition_order', {
      p_order_id: orderId,
      p_to: to,
      p_client_id: newClientId(),
      p_reference: reference,
      p_note: note,
    });
    setBusy(false);
    if (error) {
      setMessage(error.message);
      return;
    }
    setMessage(`Status sekarang: ${STATE_LABEL[(data as { state?: string })?.state ?? ''] ?? to}`);
    setShowDispute(false);
    onChanged();
    load();
  }

  if (message && !order) {
    return (
      <View style={styles.page}>
        <Pressable onPress={onBack}>
          <Text style={styles.link}>Kembali</Text>
        </Pressable>
        <Text style={styles.error}>{message}</Text>
      </View>
    );
  }

  if (!order) {
    return (
      <View style={styles.page}>
        <ActivityIndicator />
      </View>
    );
  }

  return (
    <ScrollView contentContainerStyle={styles.page}>
      <Pressable onPress={onBack}>
        <Text style={styles.link}>Kembali</Text>
      </Pressable>
      <Text style={styles.title}>{order.code}</Text>
      <Text style={styles.body}>{STATE_LABEL[order.state] ?? order.state}</Text>
      <Text style={styles.body}>Total: {money(order.subtotal)}</Text>

      {payment ? (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Transfer ke {payment.distributor_name}</Text>
          <Text style={styles.body}>Bank: {payment.bank_name}</Text>
          <Text style={styles.body}>Nomor rekening: {payment.bank_account}</Text>
          <Text style={styles.body}>Jumlah: {money(payment.amount)}</Text>
          <Text style={styles.note}>Tulis kode {order.code} di kolom berita transfer.</Text>
        </View>
      ) : null}

      {order.state === 'Shipped' ? (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Barang sudah diterima?</Text>
          <Pressable style={styles.button} onPress={confirmReceipt} disabled={busy}>
            <Text style={styles.buttonText}>Sudah terima</Text>
          </Pressable>
          {showDispute ? (
            <>
              <TextInput
                style={styles.input}
                placeholder="Apa masalahnya?"
                value={reason}
                onChangeText={setReason}
                multiline
              />
              <Pressable style={styles.buttonOutline} onPress={raiseDispute} disabled={busy}>
                <Text style={styles.buttonOutlineText}>Kirim laporan masalah</Text>
              </Pressable>
            </>
          ) : (
            <Pressable style={styles.buttonOutline} onPress={() => setShowDispute(true)}>
              <Text style={styles.buttonOutlineText}>Ada masalah</Text>
            </Pressable>
          )}
        </View>
      ) : null}

      {message ? <Text style={styles.note}>{message}</Text> : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 16, gap: 12 },
  title: { fontSize: 24, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 15, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  error: { fontSize: 15, color: '#9b3d2e' },
  link: { fontSize: 16, color: '#2c6b4f' },
  card: { backgroundColor: '#ffffff', borderRadius: 10, padding: 14, gap: 8 },
  cardTitle: { fontSize: 17, fontWeight: '600', color: '#1d2623' },
  input: { borderWidth: 1, borderColor: '#dcd8cc', borderRadius: 8, padding: 10, minHeight: 80, backgroundColor: '#ffffff' },
  button: { backgroundColor: '#2c6b4f', padding: 12, borderRadius: 8, alignItems: 'center' },
  buttonText: { color: '#ffffff', fontSize: 16, fontWeight: '600' },
  buttonOutline: { borderWidth: 1, borderColor: '#2c6b4f', padding: 12, borderRadius: 8, alignItems: 'center' },
  buttonOutlineText: { color: '#2c6b4f', fontSize: 16, fontWeight: '600' },
});
