import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { getSupabase } from '../lib/supabase';
import { currentUserId } from '../lib/session';
import { money } from '../lib/labels';
import {
  buildPlaceOrderPayload,
  groupByDistributor,
  newClientId,
  setQuantity,
  type CartItem,
  type DistributorGroup,
} from '../lib/cart';

type Props = {
  cart: CartItem[];
  onChange: (items: CartItem[]) => void;
  onOrdersPlaced: (distributorIds: string[]) => void;
  onBack: () => void;
};

export default function Basket({ cart, onChange, onOrdersPlaced, onBack }: Props) {
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const groups = groupByDistributor(cart);

  function changeQuantity(productId: string, quantity: number) {
    onChange(setQuantity(cart, productId, quantity));
  }

  async function send(group: DistributorGroup) {
    setMessage(null);
    const supabase = getSupabase();
    const buyerId = await currentUserId();
    if (!supabase) {
      setMessage('Konfigurasi Supabase belum diisi (lihat .env.example).');
      return;
    }
    if (!buyerId) {
      setMessage('Masuk diperlukan untuk mengirim pesanan. Masuk belum tersedia (menunggu D-001).');
      return;
    }
    setBusy(group.distributorId);
    // The client id makes a retry safe: the server returns the same order instead of a second one.
    const payload = buildPlaceOrderPayload(buyerId, group, newClientId());
    const { data, error } = await supabase.rpc('place_order', payload);
    setBusy(null);
    if (error) {
      setMessage(error.message);
      return;
    }
    const code = (data as { code?: string } | null)?.code ?? '';
    setMessage(`Pesanan ${code} sudah dikirim ke ${group.distributorName}.`);
    onOrdersPlaced([group.distributorId]);
  }

  return (
    <ScrollView contentContainerStyle={styles.page}>
      <Pressable onPress={onBack}>
        <Text style={styles.link}>Kembali ke katalog</Text>
      </Pressable>
      <Text style={styles.title}>Keranjang</Text>
      {groups.length === 0 ? <Text style={styles.body}>Keranjang kosong.</Text> : null}
      {message ? <Text style={styles.note}>{message}</Text> : null}

      {groups.map((group) => (
        <View key={group.distributorId} style={styles.card}>
          <Text style={styles.cardTitle}>{group.distributorName}</Text>
          <Text style={styles.note}>Satu pesanan untuk distributor ini.</Text>
          {group.items.map((item) => (
            <View key={item.productId} style={styles.line}>
              <Text style={styles.body}>
                {item.name} · {money(item.price)} / {item.unit}
              </Text>
              <View style={styles.row}>
                <Pressable style={styles.qty} onPress={() => changeQuantity(item.productId, item.quantity - 1)}>
                  <Text style={styles.qtyText}>−</Text>
                </Pressable>
                <Text style={styles.body}>{item.quantity}</Text>
                <Pressable style={styles.qty} onPress={() => changeQuantity(item.productId, item.quantity + 1)}>
                  <Text style={styles.qtyText}>+</Text>
                </Pressable>
              </View>
            </View>
          ))}
          <Text style={styles.body}>Total: {money(group.subtotal)}</Text>
          <Text style={styles.note}>Pembayaran dilakukan langsung ke distributor setelah distributor menerima pesanan.</Text>
          <Pressable style={styles.button} onPress={() => send(group)} disabled={busy === group.distributorId}>
            <Text style={styles.buttonText}>{busy === group.distributorId ? 'Mengirim...' : 'Kirim pesanan'}</Text>
          </Pressable>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 16, gap: 12 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  title: { fontSize: 24, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 15, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  link: { fontSize: 16, color: '#2c6b4f' },
  card: { backgroundColor: '#ffffff', borderRadius: 10, padding: 14, gap: 8 },
  cardTitle: { fontSize: 17, fontWeight: '600', color: '#1d2623' },
  line: { gap: 4, paddingVertical: 4 },
  qty: { width: 36, height: 36, borderRadius: 8, borderWidth: 1, borderColor: '#2c6b4f', alignItems: 'center', justifyContent: 'center' },
  qtyText: { fontSize: 18, color: '#2c6b4f' },
  button: { backgroundColor: '#2c6b4f', padding: 12, borderRadius: 8, alignItems: 'center' },
  buttonText: { color: '#ffffff', fontSize: 16, fontWeight: '600' },
});
