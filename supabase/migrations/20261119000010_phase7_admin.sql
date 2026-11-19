-- Phase 7: admin console and reporting. Source: docs/product-spec.md sections 4.7 (FR-26 to FR-28),
-- docs/business-requirements.md section 7 (KPIs), decision D-010 (on-time window).
--
-- Dates are Indonesian time (Asia/Jakarta). Admin only, except where noted.
-- Agent payouts (FR-22) still wait for the agent fee decision (D-008).

-- Configuration changes (FR-26). Only known keys, each with a range check. Every change keeps
-- the previous value and writes an audit row (config_audit trigger, migration 4).
create or replace function public.admin_set_config(p_key text, p_value jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_int integer;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can change configuration' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to change configuration';
  end if;
  if p_value is null or jsonb_typeof(p_value) <> 'number' then
    raise exception 'Configuration value must be a number';
  end if;
  v_int := (p_value #>> '{}')::integer;

  case p_key
    when 'minimum_commission' then
      if v_int < 0 then raise exception 'minimum_commission cannot be negative'; end if;
    when 'invoice_due_days' then
      if v_int not between 1 and 60 then raise exception 'invoice_due_days must be between 1 and 60'; end if;
    when 'overdue_block_days' then
      if v_int not between 1 and 90 then raise exception 'overdue_block_days must be between 1 and 90'; end if;
    when 'auto_confirm_days' then
      if v_int not between 1 and 60 then raise exception 'auto_confirm_days must be between 1 and 60'; end if;
    when 'agent_fee_per_order' then
      if v_int < 0 then raise exception 'agent_fee_per_order cannot be negative'; end if;
    else
      raise exception 'Unknown configuration key: %', p_key;
  end case;

  insert into public.config (key, value, reason)
  values (p_key, p_value, trim(p_reason))
  on conflict (key) do update set value = excluded.value, reason = excluded.reason;
end;
$$;

-- Category rate or restriction changes are audited too.
create or replace function public.categories_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.rate_bp is distinct from new.rate_bp or old.restricted is distinct from new.restricted then
    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
    values (auth.uid(), coalesce(public.current_role_name()::text, 'system'), 'category.updated',
            'category', new.id,
            jsonb_build_object('rate_bp', old.rate_bp, 'restricted', old.restricted),
            jsonb_build_object('rate_bp', new.rate_bp, 'restricted', new.restricted));
  end if;
  return new;
end;
$$;

create trigger categories_audit
  after update on public.categories
  for each row execute function public.categories_audit();

-- Admin blocks or lifts a distributor (suspension). A block stops new orders (place_order) and
-- hides the catalogue. Overdue blocks are lifted only by payment (apply_distributor_blocks).
create or replace function public.admin_set_distributor_block(p_distributor_id uuid, p_block boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_d public.distributors%rowtype;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can block or lift a distributor' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;
  select * into v_d from public.distributors d where d.id = p_distributor_id for update;
  if not found then
    raise exception 'Distributor not found';
  end if;

  if p_block then
    update public.distributors
       set blocked_at = now(), block_reason = 'Admin: ' || trim(p_reason)
     where id = p_distributor_id;
    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
    values (v_actor, 'admin', 'distributor.blocked_by_admin', 'distributor', p_distributor_id::text,
            jsonb_build_object('blocked', v_d.blocked_at is not null),
            jsonb_build_object('blocked', true, 'reason', trim(p_reason)));
  else
    if v_d.blocked_at is null then
      raise exception 'Distributor is not blocked';
    end if;
    if v_d.block_reason like 'Invoice overdue%' then
      raise exception 'An overdue block is lifted by payment of the invoice, not by hand';
    end if;
    update public.distributors
       set blocked_at = null, block_reason = null
     where id = p_distributor_id;
    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
    values (v_actor, 'admin', 'distributor.unblocked_by_admin', 'distributor', p_distributor_id::text,
            jsonb_build_object('blocked', true, 'reason', v_d.block_reason),
            jsonb_build_object('blocked', false, 'reason', trim(p_reason)));
  end if;
end;
$$;

-- Audit viewer (FR-28). Filters and a capped page size. Admin only.
create or replace function public.admin_search_audit(
  p_entity text default null,
  p_entity_id text default null,
  p_action text default null,
  p_from date default null,
  p_to date default null,
  p_limit integer default 100
)
returns setof public.audit_log
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admin can read the audit log' using errcode = '42501';
  end if;

  return query
    select a.*
      from public.audit_log a
     where (p_entity is null or a.entity = p_entity)
       and (p_entity_id is null or a.entity_id = p_entity_id)
       and (p_action is null or a.action = p_action)
       and (p_from is null or (a.created_at at time zone 'Asia/Jakarta')::date >= p_from)
       and (p_to is null or (a.created_at at time zone 'Asia/Jakarta')::date <= p_to)
     order by a.created_at desc, a.id desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- KPI report (FR-27) for a period, against the test targets in the business requirements.
-- Metrics: distributors approved (all time), buyers ordering, orders per week, orders confirmed,
-- on-time confirmation (D-010: confirmed by the buyer within 3 days of SHIP), dispute rate,
-- and invoices paid on time. A metric with no data is null.
create or replace function public.kpi_report(p_from date, p_to date)
returns table (metric text, value numeric, target numeric, unit text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days integer;
  v_orders integer;
  v_buyers integer;
  v_confirmed integer;
  v_shipped integer;
  v_ontime integer;
  v_disputes integer;
  v_inv_due integer;
  v_inv_paid_ontime integer;
  v_approved integer;
begin
  if not public.is_admin() then
    raise exception 'Only admin can view KPI reports' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Invalid period';
  end if;
  v_days := p_to - p_from + 1;

  select count(*) into v_orders from public.orders o
   where (o.created_at at time zone 'Asia/Jakarta')::date between p_from and p_to;

  select count(distinct o.buyer_id) into v_buyers from public.orders o
   where (o.created_at at time zone 'Asia/Jakarta')::date between p_from and p_to;

  select count(*) into v_confirmed from public.orders o
   where o.state = 'Confirmed' and (o.confirmed_at at time zone 'Asia/Jakarta')::date between p_from and p_to;

  select count(*) into v_shipped from public.orders o
   where o.shipped_at is not null and (o.shipped_at at time zone 'Asia/Jakarta')::date between p_from and p_to;

  select count(*) into v_ontime from public.orders o
   where o.confirmation_type = 'received'
     and o.shipped_at is not null
     and (o.shipped_at at time zone 'Asia/Jakarta')::date between p_from and p_to
     and o.confirmed_at <= o.shipped_at + interval '3 days';

  select count(*) into v_disputes from public.disputes d
   where (d.created_at at time zone 'Asia/Jakarta')::date between p_from and p_to;

  select count(*) into v_inv_due from public.invoices i where i.due_date between p_from and p_to;

  select count(*) into v_inv_paid_ontime from public.invoices i
   where i.due_date between p_from and p_to
     and i.status = 'paid'
     and (i.paid_at at time zone 'Asia/Jakarta')::date <= i.due_date;

  select count(*) into v_approved from public.distributors d where d.approval_status = 'approved';

  return query select 'distributors_approved'::text, v_approved::numeric, 3::numeric, 'count'::text;
  return query select 'buyers_ordering'::text, v_buyers::numeric, 10::numeric, 'count'::text;
  return query select 'orders_per_week'::text, round(v_orders * 7.0 / v_days, 1), 10::numeric, 'per week'::text;
  return query select 'orders_confirmed'::text, v_confirmed::numeric, null::numeric, 'count'::text;
  return query select 'on_time_confirmation_pct'::text,
                      case when v_shipped = 0 then null else round(100.0 * v_ontime / v_shipped, 1) end,
                      80::numeric, 'percent'::text;
  return query select 'dispute_rate_pct'::text,
                      case when v_shipped = 0 then null else round(100.0 * v_disputes / v_shipped, 1) end,
                      null::numeric, 'percent'::text;
  return query select 'invoices_paid_on_time_pct'::text,
                      case when v_inv_due = 0 then null else round(100.0 * v_inv_paid_ontime / v_inv_due, 1) end,
                      100::numeric, 'percent'::text;
end;
$$;

-- Function access.
revoke execute on function public.categories_audit() from public, anon, authenticated, service_role;

revoke execute on function public.admin_set_config(text, jsonb, text) from public, anon;
revoke execute on function public.admin_set_distributor_block(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_search_audit(text, text, text, date, date, integer) from public, anon;
revoke execute on function public.kpi_report(date, date) from public, anon;

grant execute on function public.admin_set_config(text, jsonb, text) to authenticated, service_role;
grant execute on function public.admin_set_distributor_block(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.admin_search_audit(text, text, text, date, date, integer) to authenticated, service_role;
grant execute on function public.kpi_report(date, date) to authenticated, service_role;
