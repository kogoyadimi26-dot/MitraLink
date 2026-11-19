-- Phase 7 completion: user suspension, agent payouts (gated on D-008), scheduled jobs and KPI snapshots.
-- Source: docs/product-spec.md sections 4.5 (FR-22), 4.7 (FR-26, FR-27); business requirements BR-07, BR-10, BR-11.
-- Dates are Indonesian time (Asia/Jakarta).

-- 1. User suspension --------------------------------------------------------------------------

-- Refuses a suspended user. Called at the start of every function that acts for a user.
create or replace function public.assert_account_active()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.status = 'suspended'
  ) then
    raise exception 'Account is suspended. Contact MitraLink.' using errcode = '42501';
  end if;
end;
$$;

-- Admin suspends or reinstates a user. Reason required; admin cannot suspend their own account.
create or replace function public.admin_set_user_status(p_user_id uuid, p_status text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_old text;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can change account status' using errcode = '42501';
  end if;
  if p_status not in ('active', 'suspended') then
    raise exception 'Status must be active or suspended';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;
  if p_user_id = v_actor then
    raise exception 'Admin cannot change their own account status';
  end if;

  select p.status into v_old from public.profiles p where p.id = p_user_id for update;
  if not found then
    raise exception 'User not found';
  end if;
  if v_old = p_status then
    raise exception 'Account is already %', p_status;
  end if;

  update public.profiles set status = p_status, updated_at = now() where id = p_user_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, 'admin', 'user.status_changed', 'profile', p_user_id::text,
          jsonb_build_object('status', v_old),
          jsonb_build_object('status', p_status, 'reason', trim(p_reason)));
end;
$$;

-- Add the suspension check to every function that acts for a user. Each one gets
-- "perform public.assert_account_active();" as the first statement of its body.
-- Note for future migrations: a function that is re-declared without this line loses the check.
do $patch$
declare
  f record;
  def text;
begin
  for f in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
       and p.proname in (
         'place_order', 'transition_order', 'sync_action', 'add_product', 'update_product',
         'set_product_availability', 'get_payment_instructions', 'attach_payment_proof', 'add_dispute_photo'
       )
  loop
    def := pg_get_functiondef(f.oid);
    if position('assert_account_active' in def) = 0 then
      def := regexp_replace(def, '\mbegin\M', E'begin\n  perform public.assert_account_active();', 'i');
      execute def;
    end if;
  end loop;
end
$patch$;

-- 2. Agent payouts (FR-22, BR-11). Gated: refuses to run until agent_fee_per_order is decided (D-008).

create table public.payout_orders (
  payout_id uuid not null references public.agent_payouts (id),
  order_id uuid not null unique references public.orders (id),
  primary key (payout_id, order_id)
);

alter table public.payout_orders enable row level security;
create policy payout_orders_read on public.payout_orders for select to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.agent_payouts p where p.id = payout_orders.payout_id and p.agent_id = auth.uid())
  );
revoke all on public.payout_orders from anon;
revoke insert, update, delete on public.payout_orders from authenticated;

-- Creates one payout per agent for a month (YYYY-MM). Eligible: confirmed orders with a commission
-- invoice that is paid, not yet in any payout. Run once per period.
create or replace function public.generate_agent_payouts(p_period text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_fee integer;
  v_end date;
  a record;
  v_payout uuid;
  v_count integer := 0;
begin
  if v_actor is not null and not public.is_admin() then
    raise exception 'Only admin or the scheduler can generate payouts' using errcode = '42501';
  end if;
  if p_period is null or p_period !~ '^\d{4}-\d{2}$' then
    raise exception 'Period must be in the form YYYY-MM';
  end if;

  select (c.value #>> '{}')::integer into v_fee from public.config c where c.key = 'agent_fee_per_order';
  if v_fee is null then
    raise exception 'agent_fee_per_order is not decided yet (D-008). Payouts cannot be generated.';
  end if;

  v_end := (to_date(p_period, 'YYYY-MM') + interval '1 month - 1 day')::date;

  for a in
    select o.agent_id,
           array_agg(o.id) as order_ids,
           count(*)::integer as n
      from public.orders o
     where o.agent_id is not null
       and o.state = 'Confirmed'
       and (o.confirmed_at at time zone 'Asia/Jakarta')::date <= v_end
       and exists (
         select 1 from public.invoice_orders io
           join public.invoices i on i.id = io.invoice_id
          where io.order_id = o.id and i.status = 'paid'
       )
       and not exists (select 1 from public.payout_orders po where po.order_id = o.id)
     group by o.agent_id
  loop
    if exists (select 1 from public.agent_payouts p where p.agent_id = a.agent_id and p.period = p_period) then
      raise exception 'Payouts for % already exist for this agent', p_period;
    end if;

    insert into public.agent_payouts (agent_id, period, order_count, amount, status)
    values (a.agent_id, p_period, a.n, a.n * v_fee, 'unpaid')
    returning id into v_payout;

    insert into public.payout_orders (payout_id, order_id)
    select v_payout, x from unnest(a.order_ids) as x;

    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
    values (v_actor, coalesce(public.current_role_name()::text, 'system'), 'agent_payout.generated',
            'agent_payout', v_payout::text,
            jsonb_build_object('period', p_period, 'orders', a.n, 'fee', v_fee, 'amount', a.n * v_fee));

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- Admin pays an agent payout with the bank reference (FR-22).
create or replace function public.mark_agent_payout_paid(p_payout_id uuid, p_reference text)
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
    raise exception 'Only admin can mark payouts paid' using errcode = '42501';
  end if;
  if p_reference is null or length(trim(p_reference)) = 0 then
    raise exception 'A bank reference is required';
  end if;

  select p.status into v_status from public.agent_payouts p where p.id = p_payout_id for update;
  if not found then
    raise exception 'Payout not found';
  end if;
  if v_status <> 'unpaid' then
    raise exception 'Payout is already paid';
  end if;

  update public.agent_payouts
     set status = 'paid', paid_at = now(), reference = trim(p_reference)
   where id = p_payout_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, 'admin', 'agent_payout.paid', 'agent_payout', p_payout_id::text,
          jsonb_build_object('status', 'unpaid'),
          jsonb_build_object('status', 'paid', 'reference', trim(p_reference)));
end;
$$;

-- 3. KPI snapshots and job log ------------------------------------------------------------------

create table public.job_runs (
  id bigint generated always as identity primary key,
  job text not null,
  step text not null,
  status text not null check (status in ('ok', 'skipped', 'failed')),
  detail text,
  ran_at timestamptz not null default now()
);

create table public.kpi_snapshots (
  id bigint generated always as identity primary key,
  period_type text not null check (period_type in ('weekly', 'monthly')),
  period_start date not null,
  period_end date not null,
  metric text not null,
  value numeric,
  target numeric,
  unit text not null,
  created_at timestamptz not null default now(),
  unique (period_type, period_start, metric)
);

alter table public.job_runs enable row level security;
alter table public.kpi_snapshots enable row level security;
create policy job_runs_admin_read on public.job_runs for select to authenticated using (public.is_admin());
create policy kpi_snapshots_admin_read on public.kpi_snapshots for select to authenticated using (public.is_admin());
revoke all on public.job_runs from anon, authenticated;
revoke all on public.kpi_snapshots from anon, authenticated;
grant select on public.job_runs to authenticated;
grant select on public.kpi_snapshots to authenticated;

-- KPI report: now also runs without a signed-in user (the scheduler). Signed-in users must be admin.
create or replace function public.kpi_report(p_from date, p_to date)
returns table (metric text, value numeric, target numeric, unit text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
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
  if v_actor is not null and not public.is_admin() then
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

-- Store a KPI report for a period (weekly or monthly). Re-running updates the same rows.
create or replace function public.take_kpi_snapshot(p_period_type text, p_from date, p_to date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_n integer;
begin
  if v_actor is not null and not public.is_admin() then
    raise exception 'Only admin can take KPI snapshots' using errcode = '42501';
  end if;
  if p_period_type not in ('weekly', 'monthly') then
    raise exception 'Period type must be weekly or monthly';
  end if;

  insert into public.kpi_snapshots (period_type, period_start, period_end, metric, value, target, unit)
  select p_period_type, p_from, p_to, r.metric, r.value, r.target, r.unit
    from public.kpi_report(p_from, p_to) r
  on conflict (period_type, period_start, metric)
  do update set value = excluded.value, target = excluded.target, unit = excluded.unit,
                period_end = excluded.period_end, created_at = now();

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- 4. Scheduled jobs -----------------------------------------------------------------------------

-- Runs the scheduled work. Each step logs ok, skipped (decision not made yet) or failed,
-- so one failing step does not stop the others.
--   daily:   overdue blocks (D-007); on the 1st of the month, the monthly job.
--   weekly:  invoices for last Monday to Sunday, and the weekly KPI snapshot.
--   monthly: monthly KPI snapshot for last month, and agent payouts (D-008).
create or replace function public.run_scheduled_jobs(p_job text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_from date;
  v_to date;
  v_block integer;
  v_fee integer;
  v_n integer;
begin
  if v_actor is not null and not public.is_admin() then
    raise exception 'Only admin or the scheduler can run jobs' using errcode = '42501';
  end if;

  if p_job = 'daily' then
    select (c.value #>> '{}')::integer into v_block from public.config c where c.key = 'overdue_block_days';
    if v_block is null then
      insert into public.job_runs (job, step, status, detail)
      values ('daily', 'overdue_blocks', 'skipped', 'overdue_block_days not decided (D-007)');
    else
      begin
        v_n := public.apply_distributor_blocks();
        insert into public.job_runs (job, step, status, detail)
        values ('daily', 'overdue_blocks', 'ok', 'changes: ' || v_n);
      exception when others then
        insert into public.job_runs (job, step, status, detail)
        values ('daily', 'overdue_blocks', 'failed', sqlerrm);
      end;
    end if;

    if extract(day from v_today) = 1 then
      perform public.run_scheduled_jobs('monthly');
    end if;

  elsif p_job = 'weekly' then
    -- Last full week, Monday to Sunday, Indonesian time.
    v_from := v_today - (extract(isodow from v_today)::integer - 1) - 7;
    v_to := v_from + 6;

    begin
      v_n := public.generate_weekly_invoices(v_from, v_to);
      insert into public.job_runs (job, step, status, detail)
      values ('weekly', 'invoices', 'ok', 'invoices created: ' || v_n || ' for ' || v_from || ' to ' || v_to);
    exception when others then
      insert into public.job_runs (job, step, status, detail)
      values ('weekly', 'invoices', 'failed', sqlerrm);
    end;

    begin
      v_n := public.take_kpi_snapshot('weekly', v_from, v_to);
      insert into public.job_runs (job, step, status, detail)
      values ('weekly', 'kpi_snapshot', 'ok', 'metrics stored: ' || v_n);
    exception when others then
      insert into public.job_runs (job, step, status, detail)
      values ('weekly', 'kpi_snapshot', 'failed', sqlerrm);
    end;

  elsif p_job = 'monthly' then
    v_from := date_trunc('month', v_today - 1)::date;
    v_to := (v_from + interval '1 month - 1 day')::date;

    begin
      v_n := public.take_kpi_snapshot('monthly', v_from, v_to);
      insert into public.job_runs (job, step, status, detail)
      values ('monthly', 'kpi_snapshot', 'ok', 'metrics stored: ' || v_n);
    exception when others then
      insert into public.job_runs (job, step, status, detail)
      values ('monthly', 'kpi_snapshot', 'failed', sqlerrm);
    end;

    select (c.value #>> '{}')::integer into v_fee from public.config c where c.key = 'agent_fee_per_order';
    if v_fee is null then
      insert into public.job_runs (job, step, status, detail)
      values ('monthly', 'agent_payouts', 'skipped', 'agent_fee_per_order not decided (D-008)');
    else
      begin
        v_n := public.generate_agent_payouts(to_char(v_from, 'YYYY-MM'));
        insert into public.job_runs (job, step, status, detail)
        values ('monthly', 'agent_payouts', 'ok', 'payouts created: ' || v_n);
      exception when others then
        insert into public.job_runs (job, step, status, detail)
        values ('monthly', 'agent_payouts', 'failed', sqlerrm);
      end;
    end if;

  else
    raise exception 'Unknown job: %', p_job;
  end if;
end;
$$;

-- Scheduler (pg_cron). Times are Indonesian time converted to UTC.
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule('mitralink-daily', '0 18 * * *', $cron$select public.run_scheduled_jobs('daily')$cron$);
select cron.schedule('mitralink-weekly', '5 17 * * 0', $cron$select public.run_scheduled_jobs('weekly')$cron$);

-- Function access.
revoke execute on function public.assert_account_active() from public, anon;
revoke execute on function public.admin_set_user_status(uuid, text, text) from public, anon;
revoke execute on function public.generate_agent_payouts(text) from public, anon;
revoke execute on function public.mark_agent_payout_paid(uuid, text) from public, anon;
revoke execute on function public.kpi_report(date, date) from public, anon;
revoke execute on function public.take_kpi_snapshot(text, date, date) from public, anon;
revoke execute on function public.run_scheduled_jobs(text) from public, anon;

grant execute on function public.assert_account_active() to authenticated, service_role;
grant execute on function public.admin_set_user_status(uuid, text, text) to authenticated, service_role;
grant execute on function public.generate_agent_payouts(text) to authenticated, service_role;
grant execute on function public.mark_agent_payout_paid(uuid, text) to authenticated, service_role;
grant execute on function public.kpi_report(date, date) to authenticated, service_role;
grant execute on function public.take_kpi_snapshot(text, date, date) to authenticated, service_role;
grant execute on function public.run_scheduled_jobs(text) to authenticated, service_role;
