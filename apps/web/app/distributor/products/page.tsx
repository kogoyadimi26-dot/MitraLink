'use client';

import { useEffect, useState } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { rupiah, ui } from '@/lib/ui';

type Product = {
  id: string;
  name: string;
  unit: string;
  price: number;
  available: boolean;
  hidden_reason: string | null;
  category_id: string;
};
type Category = { id: string; name: string };

export default function ProductsPage() {
  return (
    <RoleGate role="distributor">
      <Products />
    </RoleGate>
  );
}

function Products() {
  const [rows, setRows] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [form, setForm] = useState({ category: '', name: '', unit: '', price: '' });
  const [prices, setPrices] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { data, error } = await supabase
      .from('products')
      .select('id, name, unit, price, available, hidden_reason, category_id')
      .order('name', { ascending: true });
    if (error) setMessage({ ok: false, text: error.message });
    else setRows((data as Product[]) ?? []);
    const { data: cats } = await supabase.from('categories').select('id, name').eq('restricted', false);
    setCategories((cats as Category[]) ?? []);
  }

  useEffect(() => {
    load();
  }, []);

  async function add() {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('add_product', {
      p_category_id: form.category,
      p_name: form.name,
      p_unit: form.unit,
      p_price: Number(form.price),
      p_photo_path: null,
      p_photo_bytes: null,
    });
    if (error) {
      setMessage({ ok: false, text: error.message });
      return;
    }
    setMessage({ ok: true, text: 'Produk ditambahkan.' });
    setForm({ category: '', name: '', unit: '', price: '' });
    load();
  }

  async function savePrice(id: string) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('update_product', { p_product_id: id, p_price: Number(prices[id]) });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Harga diperbarui.' });
    load();
  }

  async function toggle(p: Product) {
    const supabase = getSupabase();
    if (!supabase) return;
    const { error } = await supabase.rpc('set_product_availability', { p_product_id: p.id, p_available: !p.available });
    setMessage(error ? { ok: false, text: error.message } : { ok: true, text: 'Ketersediaan diperbarui.' });
    load();
  }

  return (
    <section style={ui.page}>
      <h1>Produk saya</h1>
      <div style={ui.card}>
        <strong>Tambah produk</strong>
        <div style={ui.row}>
          <select style={ui.input} value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
            <option value="">Pilih kategori</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <input style={ui.input} placeholder="Nama produk" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <input style={ui.input} placeholder="Satuan" value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })} />
          <input style={ui.input} placeholder="Harga (Rp)" inputMode="numeric" value={form.price} onChange={(e) => setForm({ ...form, price: e.target.value })} />
          <button style={ui.button} onClick={add}>Tambah</button>
        </div>
      </div>
      {message ? <p style={message.ok ? ui.ok : ui.error}>{message.text}</p> : null}
      <table style={ui.table}>
        <thead>
          <tr>
            <th style={ui.th}>Produk</th>
            <th style={{ ...ui.th, ...ui.right }}>Harga</th>
            <th style={ui.th}>Ubah harga</th>
            <th style={ui.th}>Tampil</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((p) => (
            <tr key={p.id}>
              <td style={ui.td}>
                {p.name} / {p.unit}
                {p.hidden_reason ? <div style={ui.error}>Disembunyikan admin: {p.hidden_reason}</div> : null}
              </td>
              <td style={{ ...ui.td, ...ui.right }}>{rupiah(p.price)}</td>
              <td style={ui.td}>
                <div style={ui.row}>
                  <input style={{ ...ui.input, width: 120 }} inputMode="numeric" placeholder={String(p.price)} value={prices[p.id] ?? ''} onChange={(e) => setPrices({ ...prices, [p.id]: e.target.value })} />
                  <button style={ui.buttonOutline} onClick={() => savePrice(p.id)} disabled={!prices[p.id]}>Simpan</button>
                </div>
              </td>
              <td style={ui.td}>
                <button style={ui.buttonOutline} onClick={() => toggle(p)} disabled={!!p.hidden_reason && !p.available}>
                  {p.available ? 'Sembunyikan' : 'Tampilkan'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
