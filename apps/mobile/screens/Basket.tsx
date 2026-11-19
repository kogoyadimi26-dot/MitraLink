import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { getSupabase } from '../lib/supabase';
import { currentUserId } from '../lib/session';
import { money } from '../lib/labels';
import { groupByDistributor, setQuantity, type CartItem, type DistributorGroup } from '../lib/cart';
import type { ActionKind } from '../lib/outbox';

type Props = {
  cart: CartItem[];
  onChange: (items: CartItem[]) => void;
  onOrdersPlaced: (distributorIds: string[]) => void;
  enqueueAction: (action: ActionKind, payload: Record<string, unknown>) => string;
  onBack: () => void;
};

export default function Basket({ cart, onChange, onOrdersPlaced, enqueueAction, onBack }: Props) {
  const [message, setMessage] = useState<string | null>(null);
  const groups = groupByDistributor(cart);

  function changeQuantity(productId: string, quantity: number) {
    onChange(setQuantity(cart, productId, quantity));
  }

  // The order is saved on the phone at once and sent when online. Its client id is the order's
  // client id, so a retry never creates a second order.
  async function send(group: DistributorGroup) {
    setMessage(null);
    const buyerId = await currentUserId();
    if (!buyerId) {
      setMessage('Masuk diperlukan untuk mengirim pesanan.');
      return;
    }
    enqueueAction('place_order', {
      buyer_id: buyerId,
      distributor_id: group.distributorId,
      items: group.items.map((i) => ({ product_id: i.productId, quantity: i.quantity })),
    });
    setMessage(`Pesanan ke ${group.distributorName} disimpan. Akan dikirim saat tersambung.`);
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
          <Pressable style={styles.button} onPress={() => send(group)}>
            <Text style={styles.buttonText}>Kirim pesanan</Text>
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
