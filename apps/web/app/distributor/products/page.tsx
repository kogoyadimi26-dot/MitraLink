'use client';

import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react';
import RoleGate from '@/components/RoleGate';
import { getSupabase } from '@/lib/supabase';
import { rupiah } from '@/lib/ui';

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
type Notice = { ok: boolean; text: string };

const AVATAR_COLOURS = ['#2c6b4f', '#8a5a2b', '#3d5a80', '#7a4e7e', '#9b5d3e', '#4f7a3a'];

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
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState('all');
  const [adding, setAdding] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);

  async function load() {
    const supabase = getSupabase();
    if (!supabase) return;
    const [products, cats] = await Promise.all([
      supabase
        .from('products')
        .select('id, name, unit, price, available, hidden_reason, category_id')
        .order('name', { ascending: true }),
      supabase.from('categories').select('id, name').eq('restricted', false).order('name', { ascending: true }),
    ]);
    if (products.error) setNotice({ ok: false, text: products.error.message });
    else setRows((products.data as Product[]) ?? []);
    setCategories((cats.data as Category[]) ?? []);
    setLoading(false);
  }

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(null), 3500);
    return () => clearTimeout(timer);
  }, [notice]);

  const categoryName = useMemo(() => new Map(categories.map((c) => [c.id, c.name])), [categories]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter(
      (p) => (filter === 'all' || p.category_id === filter) && (q === '' || p.name.toLowerCase().includes(q)),
    );
  }, [rows, query, filter]);

  const shownCount = rows.filter((p) => p.available && !p.hidden_reason).length;

  async function run(rpc: string, args: Record<string, unknown>, okText: string): Promise<boolean> {
    const supabase = getSupabase();
    if (!supabase) return false;
    const { error } = await supabase.rpc(rpc, args);
    if (error) {
      setNotice({ ok: false, text: error.message });
      return false;
    }
    setNotice({ ok: true, text: okText });
    await load();
    return true;
  }

  async function savePrice(p: Product, value: number): Promise<boolean> {
    setBusyId(p.id);
    const ok = await run('update_product', { p_product_id: p.id, p_price: value }, 'Harga diperbarui.');
    setBusyId(null);
    return ok;
  }

  async function toggle(p: Product) {
    setBusyId(p.id);
    await run(
      'set_product_availability',
      { p_product_id: p.id, p_available: !p.available },
      p.available ? 'Produk disembunyikan dari pembeli.' : 'Produk tampil untuk pembeli.',
    );
    setBusyId(null);
  }

  return (
    <section className="stack-lg">
      <header className="page-head">
        <div>
          <p className="eyebrow">Distributor</p>
          <h1 className="page-title">Produk saya</h1>
          <p className="muted">Atur produk yang tampil untuk pembeli di kotamu.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setAdding(true)}>
          + Tambah produk
        </button>
      </header>

      <div className="stats">
        <Stat label="Total produk" value={rows.length} />
        <Stat label="Tampil" value={shownCount} tone="ok" />
        <Stat label="Tidak tampil" value={rows.length - shownCount} tone="warn" />
      </div>

      <div className="toolbar">
        <label className="search">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          <input
            className="input"
            type="search"
            placeholder="Cari nama produk"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Cari produk"
          />
        </label>
        <div className="chips" aria-label="Filter kategori">
          <button className={`chip ${filter === 'all' ? 'chip-active' : ''}`} onClick={() => setFilter('all')}>
            Semua
          </button>
          {categories.map((c) => (
            <button
              key={c.id}
              className={`chip ${filter === c.id ? 'chip-active' : ''}`}
              onClick={() => setFilter(c.id)}
            >
              {c.name}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="grid-products" aria-busy="true">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="product-card skeleton" />
          ))}
        </div>
      ) : rows.length === 0 ? (
        <EmptyState
          title="Belum ada produk"
          text="Tambah produk pertama Anda. Pembeli di kotamu akan melihatnya di katalog."
          action={
            <button className="btn btn-primary" onClick={() => setAdding(true)}>
              + Tambah produk
            </button>
          }
        />
      ) : visible.length === 0 ? (
        <EmptyState title="Tidak ada produk yang cocok" text="Coba kata kunci lain atau pilih kategori yang berbeda." />
      ) : (
        <div className="grid-products">
          {visible.map((p) => (
            <ProductCard
              key={p.id}
              product={p}
              category={categoryName.get(p.category_id) ?? ''}
              busy={busyId === p.id}
              onToggle={() => toggle(p)}
              onSavePrice={(value) => savePrice(p, value)}
            />
          ))}
        </div>
      )}

      {adding ? (
        <AddProductDialog
          categories={categories}
          onClose={() => setAdding(false)}
          onAdded={async () => {
            setNotice({ ok: true, text: 'Produk ditambahkan.' });
            await load();
          }}
        />
      ) : null}

      {notice ? (
        <div className={`toast ${notice.ok ? 'toast-ok' : 'toast-err'}`} role="status">
          {notice.text}
        </div>
      ) : null}
    </section>
  );
}

function Stat({ label, value, tone }: { label: string; value: number; tone?: 'ok' | 'warn' }) {
  return (
    <div className={`stat ${tone ? `stat-${tone}` : ''}`}>
      <span className="stat-value">{value}</span>
      <span className="stat-label">{label}</span>
    </div>
  );
}

function EmptyState({ title, text, action }: { title: string; text: string; action?: ReactNode }) {
  return (
    <div className="empty">
      <h3>{title}</h3>
      <p className="muted">{text}</p>
      {action}
    </div>
  );
}

function StatusBadge({ product }: { product: Product }) {
  if (product.hidden_reason) {
    return (
      <span className="badge badge-danger" title={product.hidden_reason}>
        Disembunyikan admin
      </span>
    );
  }
  if (!product.available) return <span className="badge badge-warn">Tidak tersedia</span>;
  return <span className="badge badge-ok">Tampil</span>;
}

function avatarColour(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  return AVATAR_COLOURS[hash % AVATAR_COLOURS.length] ?? '#2c6b4f';
}

function ProductCard({
  product,
  category,
  busy,
  onToggle,
  onSavePrice,
}: {
  product: Product;
  category: string;
  busy: boolean;
  onToggle: () => void;
  onSavePrice: (value: number) => Promise<boolean>;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const hiddenByAdmin = product.hidden_reason !== null && product.hidden_reason !== '';
  const shown = product.available && !hiddenByAdmin;
  const draftValue = Number(draft);
  const draftValid = Number.isInteger(draftValue) && draftValue > 0;

  function startEdit() {
    setDraft(String(product.price));
    setEditing(true);
  }

  async function save() {
    if (!draftValid || busy) return;
    if (await onSavePrice(draftValue)) setEditing(false);
  }

  return (
    <article className={`product-card ${shown ? '' : 'product-card-off'}`}>
      <div className="product-top">
        <div className="avatar" style={{ background: avatarColour(product.name) }} aria-hidden>
          {product.name.charAt(0).toUpperCase()}
        </div>
        <StatusBadge product={product} />
      </div>

      <div className="product-info">
        <h3>{product.name}</h3>
        <p className="muted">
          {category || 'Tanpa kategori'} · per {product.unit}
        </p>
      </div>

      {editing ? (
        <div className="price-edit">
          <div className="price-input">
            <span>Rp</span>
            <input
              autoFocus
              inputMode="numeric"
              value={draft}
              aria-label={`Harga baru untuk ${product.name}`}
              onChange={(e) => setDraft(e.target.value.replace(/\D/g, ''))}
              onKeyDown={(e) => {
                if (e.key === 'Enter') save();
                if (e.key === 'Escape') setEditing(false);
              }}
            />
          </div>
          <div className="row-gap">
            <button className="btn btn-primary btn-sm" onClick={save} disabled={!draftValid || busy}>
              Simpan
            </button>
            <button className="btn btn-ghost btn-sm" onClick={() => setEditing(false)}>
              Batal
            </button>
          </div>
        </div>
      ) : (
        <div className="product-foot">
          <p className="price">{rupiah(product.price)}</p>
          <button className="btn btn-ghost btn-sm" onClick={startEdit} disabled={busy}>
            Ubah harga
          </button>
        </div>
      )}

      <div className="product-toggle">
        <span className="muted">{shown ? 'Tampil untuk pembeli' : hiddenByAdmin ? 'Ditahan admin' : 'Tidak tampil'}</span>
        <button
          role="switch"
          aria-checked={product.available}
          aria-label={`Tampilkan ${product.name}`}
          className={`switch ${product.available ? 'switch-on' : ''}`}
          onClick={onToggle}
          disabled={busy || (hiddenByAdmin && !product.available)}
        >
          <span className="switch-knob" />
        </button>
      </div>
    </article>
  );
}

function Field({ label, error, children }: { label: string; error?: string; children: ReactNode }) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {error ? <span className="field-error">{error}</span> : null}
    </label>
  );
}

function AddProductDialog({
  categories,
  onClose,
  onAdded,
}: {
  categories: Category[];
  onClose: () => void;
  onAdded: () => Promise<void>;
}) {
  const [categoryId, setCategoryId] = useState('');
  const [name, setName] = useState('');
  const [unit, setUnit] = useState('');
  const [price, setPrice] = useState('');
  const [tried, setTried] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const priceValue = Number(price);
  const errors = {
    category: categoryId === '' ? 'Pilih kategori.' : '',
    name: name.trim().length < 2 ? 'Nama produk minimal 2 huruf.' : '',
    unit: unit.trim() === '' ? 'Isi satuan, misal: karung, dus, kg.' : '',
    price: !Number.isInteger(priceValue) || priceValue <= 0 ? 'Isi harga dalam rupiah, misal 85000.' : '',
  };
  const valid = Object.values(errors).every((msg) => msg === '');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setTried(true);
    if (!valid) return;
    const supabase = getSupabase();
    if (!supabase) {
      setError('Konfigurasi Supabase belum diisi.');
      return;
    }
    setSaving(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc('add_product', {
      p_category_id: categoryId,
      p_name: name.trim(),
      p_unit: unit.trim(),
      p_price: priceValue,
      p_photo_path: null,
      p_photo_bytes: null,
    });
    setSaving(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    await onAdded();
    onClose();
  }

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="dialog" role="dialog" aria-modal="true" aria-labelledby="add-product-title">
        <div className="dialog-head">
          <h2 id="add-product-title">Tambah produk</h2>
          <button className="icon-btn" onClick={onClose} aria-label="Tutup">
            ×
          </button>
        </div>

        <form onSubmit={submit} className="form" noValidate>
          <Field label="Kategori" error={tried ? errors.category : ''}>
            <select className="input" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">Pilih kategori</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Nama produk" error={tried ? errors.name : ''}>
            <input
              className="input"
              value={name}
              placeholder="Contoh: Beras premium 5 kg"
              onChange={(e) => setName(e.target.value)}
            />
          </Field>

          <div className="form-row">
            <Field label="Satuan" error={tried ? errors.unit : ''}>
              <input
                className="input"
                value={unit}
                placeholder="karung, dus, kg"
                onChange={(e) => setUnit(e.target.value)}
              />
            </Field>
            <Field label="Harga (Rp)" error={tried ? errors.price : ''}>
              <input
                className="input"
                inputMode="numeric"
                value={price}
                placeholder="85000"
                onChange={(e) => setPrice(e.target.value.replace(/\D/g, ''))}
              />
              {priceValue > 0 ? <span className="hint">{rupiah(priceValue)}</span> : null}
            </Field>
          </div>

          <p className="hint">Foto produk bisa ditambahkan nanti. Harga dalam rupiah utuh.</p>
          {error ? <p className="error-text">{error}</p> : null}

          <div className="dialog-actions">
            <button type="button" className="btn btn-ghost" onClick={onClose}>
              Batal
            </button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Menyimpan...' : 'Simpan produk'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
