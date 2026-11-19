import { describe, expect, it } from 'vitest';
import {
  addToCart,
  buildPlaceOrderPayload,
  groupByDistributor,
  newClientId,
  setQuantity,
  type CartItem,
} from '../lib/cart';

const beras = { productId: 'p1', distributorId: 'd1', distributorName: 'CV Papua', name: 'Beras', unit: 'karung', price: 15000 };
const gula = { productId: 'p2', distributorId: 'd1', distributorName: 'CV Papua', name: 'Gula', unit: 'kg', price: 16000 };
const kipas = { productId: 'p3', distributorId: 'd2', distributorName: 'Toko Elektronik', name: 'Kipas', unit: 'unit', price: 500000 };

describe('cart', () => {
  it('adds a product once and counts up', () => {
    let items: CartItem[] = addToCart([], beras);
    items = addToCart(items, beras);
    expect(items).toHaveLength(1);
    expect(items[0]?.quantity).toBe(2);
  });

  it('removes a line when the quantity is zero, and keeps whole numbers only', () => {
    let items = addToCart([], beras);
    items = setQuantity(items, 'p1', 3.9);
    expect(items[0]?.quantity).toBe(3);
    items = setQuantity(items, 'p1', 0);
    expect(items).toHaveLength(0);
  });

  it('groups lines by distributor, with a subtotal for each', () => {
    let items = addToCart([], beras);
    items = setQuantity(addToCart(items, gula), 'p2', 2);
    items = addToCart(items, kipas);
    const groups = groupByDistributor(items);
    expect(groups.map((g) => g.distributorId)).toEqual(['d1', 'd2']);
    expect(groups[0]?.subtotal).toBe(15000 + 2 * 16000);
    expect(groups[1]?.subtotal).toBe(500000);
  });

  it('builds the place_order arguments for one distributor', () => {
    const items = setQuantity(addToCart([], beras), 'p1', 10);
    const group = groupByDistributor(items)[0]!;
    expect(buildPlaceOrderPayload('buyer-1', group, 'client-1')).toEqual({
      p_client_id: 'client-1',
      p_buyer_id: 'buyer-1',
      p_distributor_id: 'd1',
      p_items: [{ product_id: 'p1', quantity: 10 }],
    });
  });
});

describe('newClientId', () => {
  it('makes a version 4 UUID shape', () => {
    const id = newClientId();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('gives different ids for different calls', () => {
    expect(newClientId()).not.toBe(newClientId());
  });
});
