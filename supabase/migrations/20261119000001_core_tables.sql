-- MitraLink core schema. Source: docs/product-spec.md section 7.
-- Money is whole rupiah (BR-15). Category rates are basis points.
-- Order state changes happen only through functions (see 20261119000004).

create type public.user_role as enum ('buyer', 'agent', 'distributor', 'admin');

create type public.order_state as enum (
  'Placed', 'Accepted', 'Declined', 'AwaitingPayment', 'Paid',
  'Shipped', 'Confirmed', 'Disputed', 'Cancelled'
);

-- Towns. Launch towns are active (decision D-004).
create table public.towns (
  id smallint generated always as identity primary key,
  code text not null unique check (code ~ '^[A-Z]{1,2}$'),
  name text not null,
  active boolean not null default false
);

-- One profile per auth user. Role decides what the user can do.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  role public.user_role not null,
  phone text not null unique check (phone ~ '^\+62[0-9]{8,13}$'),
  full_name text not null check (length(trim(full_name)) > 0),
  status text not null default 'active' check (status in ('active', 'suspended')),
  language text not null default 'id',
  terms_version text,
  terms_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Product categories with the test-phase rate (BR-03). Restricted goods have no rate.
create table public.categories (
  id text primary key check (id ~ '^[a-z_]+$'),
  name text not null,
  restricted boolean not null default false,
  rate_bp integer check (rate_bp is null or rate_bp between 0 and 10000),
  check ((restricted and rate_bp is null) or (not restricted and rate_bp is not null))
);

-- Decided configuration only. A key that is absent means "not decided yet":
-- D-006 auto_confirm_days, D-007 overdue_block_days, D-008 agent_fee_per_order.
create table public.config (
  key text primary key,
  value jsonb not null,
  previous_value jsonb,
  reason text,
  changed_by uuid references auth.users (id),
  changed_at timestamptz not null default now()
);

create table public.buyers (
  id uuid primary key references public.profiles (id) on delete restrict,
  business_name text not null check (length(trim(business_name)) > 0),
  business_type text not null check (business_type in ('kios', 'warung', 'sekolah', 'gereja', 'lainnya')),
  town_id smallint not null references public.towns (id),
  agent_id uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.agents (
  id uuid primary key references public.profiles (id) on delete restrict,
  town_id smallint not null references public.towns (id),
  created_at timestamptz not null default now()
);

-- Public-to-buyers distributor details. Sensitive details are in distributor_private.
create table public.distributors (
  id uuid primary key references public.profiles (id) on delete restrict,
  business_name text not null check (length(trim(business_name)) > 0),
  town_id smallint not null references public.towns (id),
  approval_status text not null default 'pending'
    check (approval_status in ('pending', 'approved', 'rejected', 'suspended')),
  approved_at timestamptz,
  approved_by uuid references public.profiles (id),
  commission_terms_version text,
  blocked_at timestamptz,
  block_reason text,
  created_at timestamptz not null default now(),
  check ((approval_status = 'approved') = (approved_at is not null))
);

-- Tax and bank details: visible only to the distributor and admin.
create table public.distributor_private (
  id uuid primary key references public.distributors (id) on delete restrict,
  tax_number text,
  bank_name text,
  bank_account text,
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors (id),
  category_id text not null references public.categories (id),
  name text not null check (length(trim(name)) > 0),
  unit text not null check (length(trim(unit)) > 0),
  price integer not null check (price >= 0),
  available boolean not null default true,
  photo_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Per-town sequence for order codes PDC-<TOWN>-<NNNN>. Never reused.
create table public.town_sequences (
  town_id smallint primary key references public.towns (id),
  last_seq integer not null default 0 check (last_seq >= 0)
);

-- One order per distributor per basket.
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  client_id uuid not null unique,
  buyer_id uuid not null references public.buyers (id),
  agent_id uuid references public.agents (id),
  distributor_id uuid not null references public.distributors (id),
  town_id smallint not null references public.towns (id),
  state public.order_state not null default 'Placed',
  subtotal integer not null default 0 check (subtotal >= 0),
  commission integer check (commission is null or commission >= 0),
  minimum_applied boolean,
  confirmation_type text check (confirmation_type in ('received', 'auto', 'dispute_resolved')),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  paid_at timestamptz,
  shipped_at timestamptz,
  confirmed_at timestamptz,
  -- Commission is set exactly when the order is Confirmed (BR-07).
  check ((state = 'Confirmed') = (commission is not null)),
  check ((commission is null) = (minimum_applied is null))
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  product_id uuid references public.products (id),
  category_id text not null references public.categories (id),
  name_snapshot text not null,
  unit_price integer not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  line_total integer not null check (line_total >= 0),
  check (line_total = unit_price * quantity)
);

-- Append-only history of order states (BR-13).
create table public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id),
  from_state public.order_state,
  to_state public.order_state not null,
  actor_user_id uuid references auth.users (id),
  actor_role text not null check (actor_role in ('buyer', 'agent', 'distributor', 'admin', 'system')),
  device text,
  note text,
  created_at timestamptz not null default now()
);

-- Payment evidence. In the test, a distributor marks PAID after checking the bank (BR-05).
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  method text not null default 'bank_transfer' check (method in ('bank_transfer')),
  reference text not null check (length(trim(reference)) > 0),
  amount integer not null check (amount > 0),
  marked_by uuid not null references auth.users (id),
  marked_at timestamptz not null default now(),
  reversed_at timestamptz,
  reversed_by uuid references auth.users (id),
  reversal_reason text,
  check ((reversed_at is null) = (reversal_reason is null))
);

create unique index payments_one_active_per_order
  on public.payments (order_id) where reversed_at is null;

create table public.shipments (
  order_id uuid primary key references public.orders (id),
  shipped_at timestamptz not null default now(),
  marked_by uuid not null references auth.users (id)
);

create table public.confirmations (
  order_id uuid primary key references public.orders (id),
  type text not null check (type in ('received', 'auto', 'dispute_resolved')),
  confirmed_by uuid references auth.users (id),
  confirmed_at timestamptz not null default now()
);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  reason text not null check (length(trim(reason)) > 0),
  description text,
  photo_paths text[] not null default '{}' check (cardinality(photo_paths) <= 3),
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolution text,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  resolved_by uuid references auth.users (id),
  resolved_at timestamptz,
  check ((status = 'resolved') = (resolved_at is not null))
);

-- Commission per category within an order, with the rate used (FR-17).
create table public.commission_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  category_id text not null references public.categories (id),
  rate_bp integer not null check (rate_bp between 0 and 10000),
  basis_amount integer not null check (basis_amount >= 0),
  commission_amount integer not null check (commission_amount >= 0),
  unique (order_id, category_id)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null unique,
  distributor_id uuid not null references public.distributors (id),
  period_start date not null,
  period_end date not null,
  total_commission integer not null check (total_commission >= 0),
  due_date date not null,
  status text not null default 'unpaid' check (status in ('unpaid', 'paid')),
  paid_at timestamptz,
  bank_reference text,
  distributor_tax_number text,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  check (period_end >= period_start),
  check ((status = 'paid') = (paid_at is not null))
);

create table public.invoice_orders (
  invoice_id uuid not null references public.invoices (id),
  order_id uuid not null unique references public.orders (id),
  primary key (invoice_id, order_id)
);

create table public.agent_payouts (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents (id),
  period text not null check (period ~ '^\d{4}-\d{2}$'),
  order_count integer not null check (order_count >= 0),
  amount integer not null check (amount >= 0),
  status text not null default 'unpaid' check (status in ('unpaid', 'paid')),
  paid_at timestamptz,
  reference text,
  unique (agent_id, period),
  check ((status = 'paid') = (paid_at is not null))
);

-- Append-only audit log (BR-13). No update or delete grants are given later.
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid,
  actor_role text not null,
  action text not null,
  entity text not null,
  entity_id text not null,
  before jsonb,
  after jsonb,
  device text,
  created_at timestamptz not null default now()
);

-- Idempotency for actions that can be retried (NFR-03).
create table public.client_actions (
  client_id uuid primary key,
  actor_user_id uuid not null,
  action text not null,
  entity_id text,
  result jsonb not null,
  created_at timestamptz not null default now()
);

-- Allowed order transitions and who may trigger each (product spec section 3).
create table public.order_transitions (
  from_state public.order_state not null,
  to_state public.order_state not null,
  allowed_actors text[] not null
    check (allowed_actors <@ array['buyer', 'agent', 'distributor', 'admin', 'system']::text[]),
  primary key (from_state, to_state)
);

create index orders_distributor_state_idx on public.orders (distributor_id, state);
create index orders_buyer_idx on public.orders (buyer_id);
create index orders_agent_idx on public.orders (agent_id) where agent_id is not null;
create index order_events_order_idx on public.order_events (order_id, created_at);
create index products_distributor_idx on public.products (distributor_id);
create index invoices_distributor_status_idx on public.invoices (distributor_id, status);
create index audit_log_entity_idx on public.audit_log (entity, entity_id);
