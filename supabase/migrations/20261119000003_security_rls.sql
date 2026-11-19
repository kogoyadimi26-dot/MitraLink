-- Row-level security and grants. Source: docs/product-spec.md section 6 (permissions)
-- and NFR-06 (each user sees only their own data).
--
-- Rule of thumb: authenticated users read through policies; they write orders,
-- payments, shipments, confirmations, disputes and invoices only through
-- security-definer functions (20261119000004). Audit and order event tables are
-- append-only.

-- Helpers. Security definer so policies can read profiles without recursion.
create or replace function public.current_role_name()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_role_name() = 'admin', false)
$$;

-- Enable RLS on every table. A table with RLS and no policy denies everything.
alter table public.towns enable row level security;
alter table public.categories enable row level security;
alter table public.config enable row level security;
alter table public.profiles enable row level security;
alter table public.buyers enable row level security;
alter table public.agents enable row level security;
alter table public.distributors enable row level security;
alter table public.distributor_private enable row level security;
alter table public.products enable row level security;
alter table public.town_sequences enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_events enable row level security;
alter table public.payments enable row level security;
alter table public.shipments enable row level security;
alter table public.confirmations enable row level security;
alter table public.disputes enable row level security;
alter table public.commission_lines enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_orders enable row level security;
alter table public.agent_payouts enable row level security;
alter table public.audit_log enable row level security;
alter table public.client_actions enable row level security;
alter table public.order_transitions enable row level security;

-- Reference data: readable by signed-in users, changed by admin only.
create policy towns_read on public.towns for select to authenticated using (true);
create policy towns_admin on public.towns for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy categories_read on public.categories for select to authenticated using (true);
create policy categories_admin on public.categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy config_read on public.config for select to authenticated using (true);
create policy config_admin on public.config for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy transitions_read on public.order_transitions for select to authenticated using (true);

-- Profiles: own profile or admin. Created and changed by server processes only.
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Buyers: self, the buyer's agent, or admin.
create policy buyers_read on public.buyers for select to authenticated
  using (id = auth.uid() or agent_id = auth.uid() or public.is_admin());
create policy buyers_admin on public.buyers for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Agents: self or admin.
create policy agents_read on public.agents for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy agents_admin on public.agents for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Distributors: approved ones are visible to signed-in users (name, town, status only).
-- Tax and bank details live in distributor_private.
create policy distributors_read on public.distributors for select to authenticated
  using (approval_status = 'approved' or id = auth.uid() or public.is_admin());
create policy distributors_admin on public.distributors for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy distributor_private_read on public.distributor_private for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy distributor_private_write on public.distributor_private for all to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Products: visible when the distributor is approved and not blocked, or to the
-- distributor who owns them, or to admin. Writes only by an approved owner, or admin.
create policy products_read on public.products for select to authenticated
  using (
    exists (
      select 1 from public.distributors d
      where d.id = products.distributor_id
        and d.approval_status = 'approved'
        and d.blocked_at is null
    )
    or distributor_id = auth.uid()
    or public.is_admin()
  );
create policy products_owner_write on public.products for all to authenticated
  using (
    public.is_admin()
    or (
      distributor_id = auth.uid()
      and exists (
        select 1 from public.distributors d
        where d.id = products.distributor_id and d.approval_status = 'approved'
      )
    )
  )
  with check (
    public.is_admin()
    or (
      distributor_id = auth.uid()
      and exists (
        select 1 from public.distributors d
        where d.id = products.distributor_id and d.approval_status = 'approved'
      )
    )
  );

-- Orders: buyer, their agent, the distributor, or admin. No direct writes.
create policy orders_read on public.orders for select to authenticated
  using (
    buyer_id = auth.uid()
    or agent_id = auth.uid()
    or distributor_id = auth.uid()
    or public.is_admin()
  );

-- Order detail tables follow the visibility of their order.
create policy order_items_read on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_items.order_id));

create policy order_events_read on public.order_events for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_events.order_id));

create policy payments_read on public.payments for select to authenticated
  using (exists (select 1 from public.orders o where o.id = payments.order_id));

create policy shipments_read on public.shipments for select to authenticated
  using (exists (select 1 from public.orders o where o.id = shipments.order_id));

create policy confirmations_read on public.confirmations for select to authenticated
  using (exists (select 1 from public.orders o where o.id = confirmations.order_id));

create policy disputes_read on public.disputes for select to authenticated
  using (exists (select 1 from public.orders o where o.id = disputes.order_id));

-- Commission is internal to MitraLink and the distributor, not the buyer or agent.
create policy commission_lines_read on public.commission_lines for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.id = commission_lines.order_id and o.distributor_id = auth.uid()
    )
  );

-- Invoices: the distributor they are issued to, or admin.
create policy invoices_read on public.invoices for select to authenticated
  using (distributor_id = auth.uid() or public.is_admin());
create policy invoices_admin on public.invoices for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy invoice_orders_read on public.invoice_orders for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.invoices i
      where i.id = invoice_orders.invoice_id and i.distributor_id = auth.uid()
    )
  );
create policy invoice_orders_admin on public.invoice_orders for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Agent payouts: the agent paid, or admin.
create policy agent_payouts_read on public.agent_payouts for select to authenticated
  using (agent_id = auth.uid() or public.is_admin());
create policy agent_payouts_admin on public.agent_payouts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Audit log: admin reads. Nobody writes directly; functions write it.
create policy audit_log_admin_read on public.audit_log for select to authenticated
  using (public.is_admin());

-- town_sequences and client_actions: no policies. Only security-definer functions use them.

-- Grants: start from nothing for anonymous users, then allow what RLS governs.
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from public, anon;

-- Append-only: no update, delete or truncate on audit and event history, for anyone.
revoke update, delete, truncate on public.audit_log from public, anon, authenticated, service_role;
revoke update, delete, truncate on public.order_events from public, anon, authenticated, service_role;
revoke update, delete, truncate on public.client_actions from public, anon, authenticated, service_role;

-- Functions that users may call directly. Everything else is internal.
grant execute on function public.current_role_name() to authenticated, service_role;
grant execute on function public.is_admin() to authenticated, service_role;
