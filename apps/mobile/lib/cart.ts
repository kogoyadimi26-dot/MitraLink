/**
 * Basket rules for the buyer app. Pure functions, so they can be tested without a device.
 *
 * One order is placed per distributor (product spec FR-09), so the basket is grouped by distributor
 * and each group is sent as its own place_order call. Buyers see prices only: commission is paid by
 * the distributor, so the app never shows it to buyers (BR-01, BR-04).
 */

export type CartItem = {
  productId: string;
  distributorId: string;
  distributorName: string;
  name: string;
  unit: string;
  price: number;
  quantity: number;
};

export type DistributorGroup = {
  distributorId: string;
  distributorName: string;
  items: CartItem[];
  subtotal: number;
};

export type PlaceOrderPayload = {
  p_client_id: string;
  p_buyer_id: string;
  p_distributor_id: string;
  p_items: { product_id: string; quantity: number }[];
};

export function addToCart(items: CartItem[], product: Omit<CartItem, 'quantity'>): CartItem[] {
  const existing = items.find((i) => i.productId === product.productId);
  if (existing) {
    return items.map((i) => (i.productId === product.productId ? { ...i, quantity: i.quantity + 1 } : i));
  }
  return [...items, { ...product, quantity: 1 }];
}

/** Sets a quantity. Zero or less removes the line. Whole numbers only. */
export function setQuantity(items: CartItem[], productId: string, quantity: number): CartItem[] {
  const q = Math.floor(quantity);
  if (q <= 0) return items.filter((i) => i.productId !== productId);
  return items.map((i) => (i.productId === productId ? { ...i, quantity: q } : i));
}

export function groupByDistributor(items: CartItem[]): DistributorGroup[] {
  const groups = new Map<string, DistributorGroup>();
  for (const item of items) {
    const g = groups.get(item.distributorId) ?? {
      distributorId: item.distributorId,
      distributorName: item.distributorName,
      items: [],
      subtotal: 0,
    };
    g.items.push(item);
    g.subtotal += item.price * item.quantity;
    groups.set(item.distributorId, g);
  }
  return [...groups.values()];
}

/** Arguments for the place_order function, for one distributor group. */
export function buildPlaceOrderPayload(buyerId: string, group: DistributorGroup, clientId: string): PlaceOrderPayload {
  return {
    p_client_id: clientId,
    p_buyer_id: buyerId,
    p_distributor_id: group.distributorId,
    p_items: group.items.map((i) => ({ product_id: i.productId, quantity: i.quantity })),
  };
}

/** A random version 4 UUID. Used as the client id, so a retry never creates a second order. */
export function newClientId(random: () => number = Math.random): string {
  const hex = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      out += '-';
    } else if (i === 14) {
      out += '4';
    } else if (i === 19) {
      out += hex[(Math.floor(random() * 16) & 0x3) | 0x8];
    } else {
      out += hex[Math.floor(random() * 16)];
    }
  }
  return out;
}
