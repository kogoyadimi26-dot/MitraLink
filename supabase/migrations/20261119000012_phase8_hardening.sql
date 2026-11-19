-- Phase 8 hardening: security and performance findings from the Supabase advisors.
--
-- 1. Scheduler and admin-only job functions are no longer callable by signed-in users directly.
--    Each already checked for admin inside; this removes the direct grant as well.
-- 2. Row-level security policies call auth.uid() once per query, not once per row.
-- 3. Indexes for foreign keys (the advisor flags these as slow on large tables).
--
-- Not changed (on purpose): admin "all" policies that overlap read policies (small performance cost,
-- and rewriting them would make the write rules harder to read); unused indexes on new tables.

-- 1. Scheduler-only functions. Only the scheduler (postgres, via pg_cron) and the service role call these.
revoke execute on function public.run_scheduled_jobs(text) from authenticated;
revoke execute on function public.take_kpi_snapshot(text, date, date) from authenticated;
revoke execute on function public.apply_distributor_blocks(date) from authenticated;

-- 2. Policies: (select auth.uid()) instead of auth.uid(). Same meaning, evaluated once per query.
do $policies$
declare
  p record;
  new_qual text;
  new_check text;
begin
  for p in
    select policyname, tablename, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') like '%auth.uid()%' or coalesce(with_check, '') like '%auth.uid()%')
  loop
    new_qual := replace(replace(p.qual, '(select auth.uid())', 'auth.uid()'), 'auth.uid()', '(select auth.uid())');
    new_check := replace(replace(p.with_check, '(select auth.uid())', 'auth.uid()'), 'auth.uid()', '(select auth.uid())');
    if p.qual is not null then
      execute format('alter policy %I on public.%I using (%s)', p.policyname, p.tablename, new_qual);
    end if;
    if p.with_check is not null then
      execute format('alter policy %I on public.%I with check (%s)', p.policyname, p.tablename, new_check);
    end if;
  end loop;
end
$policies$;

-- 3. Indexes for foreign keys.
create index if not exists agents_town_idx on public.agents (town_id);
create index if not exists buyers_agent_idx on public.buyers (agent_id);
create index if not exists buyers_town_idx on public.buyers (town_id);
create index if not exists commission_lines_category_idx on public.commission_lines (category_id);
create index if not exists config_changed_by_idx on public.config (changed_by);
create index if not exists confirmations_confirmed_by_idx on public.confirmations (confirmed_by);
create index if not exists disputes_created_by_idx on public.disputes (created_by);
create index if not exists disputes_order_idx on public.disputes (order_id);
create index if not exists disputes_resolved_by_idx on public.disputes (resolved_by);
create index if not exists distributor_documents_distributor_idx on public.distributor_documents (distributor_id);
create index if not exists distributor_documents_uploaded_by_idx on public.distributor_documents (uploaded_by);
create index if not exists distributors_approved_by_idx on public.distributors (approved_by);
create index if not exists distributors_town_idx on public.distributors (town_id);
create index if not exists invoices_created_by_idx on public.invoices (created_by);
create index if not exists notifications_order_idx on public.notifications (order_id);
create index if not exists order_events_actor_idx on public.order_events (actor_user_id);
create index if not exists order_items_category_idx on public.order_items (category_id);
create index if not exists order_items_order_idx on public.order_items (order_id);
create index if not exists order_items_product_idx on public.order_items (product_id);
create index if not exists orders_created_by_idx on public.orders (created_by);
create index if not exists orders_town_idx on public.orders (town_id);
create index if not exists payment_proofs_order_idx on public.payment_proofs (order_id);
create index if not exists payment_proofs_uploaded_by_idx on public.payment_proofs (uploaded_by);
create index if not exists payments_marked_by_idx on public.payments (marked_by);
create index if not exists payments_reversed_by_idx on public.payments (reversed_by);
create index if not exists products_category_idx on public.products (category_id);
create index if not exists products_hidden_by_idx on public.products (hidden_by);
create index if not exists shipments_marked_by_idx on public.shipments (marked_by);
