-- Phase 6 (part 1): commission invoices. Source: docs/product-spec.md section 4.4 (FR-17 to FR-20),
-- docs/business-requirements.md BR-08, BR-10, BR-16; decision log D-007 (overdue block), D-009 (tax).
--
-- Scope here: weekly invoices per distributor, payment marking, overdue detection, the overdue
-- block (gated until D-007 is decided), and tax fields recorded but not calculated (BR-16).
-- Agent payouts (FR-22) wait for the agent fee decision (D-008), and auto-confirm waits for D-006.
--
-- Dates use Indonesian time (WIB, Asia/Jakarta), since orders are confirmed in local time.

-- Invoice numbers. Not reused.
create sequence public.invoice_number_seq;

-- Payment term in days (BR-08). Seeded at the terms' 7 days. Confirm with the founder.
insert into public.config (key, value, reason)
values ('invoice_due_days', '7'::jsonb, 'BR-08: payment due within 7 days (terms section 6.3). To confirm with founder.');

-- System-generated invoices have no signed-in creator.
alter table public.invoices alter column created_by drop not null;

-- Invoices change only through the functions below. Remove direct admin writes.
drop policy invoices_admin on public.invoices;
drop policy invoice_orders_admin on public.invoice_orders;
revoke insert, update, delete on public.invoices from anon, authenticated;
revoke insert, update, delete on public.invoice_orders from anon, authenticated;

-- Generate one invoice per distributor for orders confirmed in the period (FR-18).
-- Each order is invoiced once (invoice_orders.order_id is unique). Admin or the scheduler.
create or replace function public.generate_weekly_invoices(p_period_start date, p_period_end date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_due_days integer;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  g record;
  v_invoice_id uuid;
  v_number text;
  v_tax text;
  v_count integer := 0;
begin
  if v_actor is not null and not public.is_admin() then
    raise exception 'Only admin or the scheduler can generate invoices' using errcode = '42501';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'Invalid period';
  end if;
  if p_period_end - p_period_start > 31 then
    raise exception 'A period can be at most 31 days';
  end if;

  select (c.value #>> '{}')::integer into v_due_days from public.config c where c.key = 'invoice_due_days';
  if v_due_days is null then
    raise exception 'invoice_due_days is not configured';
  end if;

  for g in
    select o.distributor_id as dist_id,
           sum(o.commission)::integer as total,
           array_agg(o.id) as order_ids
      from public.orders o
     where o.state = 'Confirmed'
       and (o.confirmed_at at time zone 'Asia/Jakarta')::date between p_period_start and p_period_end
       and not exists (select 1 from public.invoice_orders io where io.order_id = o.id)
     group by o.distributor_id
  loop
    v_number := 'MLK-' || to_char(v_today, 'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text, 5, '0');

    select pv.tax_number into v_tax from public.distributor_private pv where pv.id = g.dist_id;

    insert into public.invoices (number, distributor_id, period_start, period_end, total_commission,
                                 due_date, distributor_tax_number, created_by)
    values (v_number, g.dist_id, p_period_start, p_period_end, g.total,
            v_today + v_due_days, v_tax, v_actor)
    returning id into v_invoice_id;

    insert into public.invoice_orders (invoice_id, order_id)
    select v_invoice_id, x from unnest(g.order_ids) as x;

    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
    values (v_actor, coalesce(public.current_role_name()::text, 'system'), 'invoice.generated', 'invoice',
            v_invoice_id::text, jsonb_build_object('number', v_number, 'total', g.total,
                                                   'orders', cardinality(g.order_ids)));

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Admin records that an invoice was paid, with the bank reference (FR-19).
create or replace function public.mark_invoice_paid(p_invoice_id uuid, p_bank_reference text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_status text;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can mark invoices paid' using errcode = '42501';
  end if;
  if p_bank_reference is null or length(trim(p_bank_reference)) = 0 then
    raise exception 'A bank reference is required';
  end if;

  select i.status into v_status from public.invoices i where i.id = p_invoice_id for update;
  if not found then
    raise exception 'Invoice not found';
  end if;
  if v_status <> 'unpaid' then
    raise exception 'Invoice is already paid';
  end if;

  update public.invoices
     set status = 'paid', paid_at = now(), bank_reference = trim(p_bank_reference)
   where id = p_invoice_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, 'admin', 'invoice.paid', 'invoice', p_invoice_id::text,
          jsonb_build_object('status', 'unpaid'),
          jsonb_build_object('status', 'paid', 'bank_reference', trim(p_bank_reference)));
end;
$$;

-- Unpaid invoices past their due date (FR-19). Admin only.
create or replace function public.overdue_invoices(p_as_of date default null)
returns table (
  invoice_id uuid,
  invoice_number text,
  distributor_id uuid,
  total_commission integer,
  due_date date,
  days_overdue integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Jakarta')::date);
begin
  if not public.is_admin() then
    raise exception 'Only admin can list overdue invoices' using errcode = '42501';
  end if;

  return query
    select i.id, i.number, i.distributor_id, i.total_commission, i.due_date,
           (v_as_of - i.due_date)::integer
      from public.invoices i
     where i.status = 'unpaid' and i.due_date < v_as_of
     order by i.due_date;
end;
$$;

-- Block or unblock distributors by overdue invoices (BR-10). Refuses to run until the
-- overdue block period is decided (D-007). Admin or the scheduler.
create or replace function public.apply_distributor_blocks(p_as_of date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_block_days integer;
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Jakarta')::date);
  d record;
  v_over boolean;
  v_count integer := 0;
begin
  if v_actor is not null and not public.is_admin() then
    raise exception 'Only admin or the scheduler can apply blocks' using errcode = '42501';
  end if;

  select (c.value #>> '{}')::integer into v_block_days from public.config c where c.key = 'overdue_block_days';
  if v_block_days is null then
    raise exception 'overdue_block_days is not decided yet (D-007). Blocks cannot be applied.';
  end if;

  for d in select dist.id, dist.blocked_at, dist.block_reason from public.distributors dist loop
    select exists (
      select 1 from public.invoices i
       where i.distributor_id = d.id
         and i.status = 'unpaid'
         and (v_as_of - i.due_date) > v_block_days
    ) into v_over;

    if v_over and d.blocked_at is null then
      update public.distributors
         set blocked_at = now(), block_reason = 'Invoice overdue (BR-10)'
       where id = d.id;
      insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
      values (v_actor, coalesce(public.current_role_name()::text, 'system'), 'distributor.blocked',
              'distributor', d.id::text, jsonb_build_object('reason', 'Invoice overdue (BR-10)'));
      v_count := v_count + 1;
    elsif not v_over and d.blocked_at is not null and d.block_reason = 'Invoice overdue (BR-10)' then
      update public.distributors
         set blocked_at = null, block_reason = null
       where id = d.id;
      insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
      values (v_actor, coalesce(public.current_role_name()::text, 'system'), 'distributor.unblocked',
              'distributor', d.id::text, jsonb_build_object('reason', 'Invoice paid or not overdue'));
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- Function access.
revoke execute on function public.generate_weekly_invoices(date, date) from public, anon;
revoke execute on function public.mark_invoice_paid(uuid, text) from public, anon;
revoke execute on function public.overdue_invoices(date) from public, anon;
revoke execute on function public.apply_distributor_blocks(date) from public, anon;

grant execute on function public.generate_weekly_invoices(date, date) to authenticated, service_role;
grant execute on function public.mark_invoice_paid(uuid, text) to authenticated, service_role;
grant execute on function public.overdue_invoices(date) to authenticated, service_role;
grant execute on function public.apply_distributor_blocks(date) to authenticated, service_role;
