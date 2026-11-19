-- Phase 7 completion test: user suspension, agent payouts (gated on D-008), scheduled jobs, KPI snapshots,
-- and the scheduler setup. Run against a development project only. Everything is rolled back: the
-- script ends by raising an error that carries the results. Expected output: "0 failing".

create or replace function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  if p is null then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
  else
    perform set_config('request.jwt.claim.sub', p::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role', 'authenticated')::text, true);
  end if;
end $$;

create temp table if not exists pg_temp.test_results (name text, ok boolean, detail text);
delete from pg_temp.test_results;

do $test$
declare
  admin_id uuid := '00000000-0000-0000-0000-00000000a901';
  dist1 uuid := '00000000-0000-0000-0000-00000000a902';
  agent1 uuid := '00000000-0000-0000-0000-00000000a903';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a904';
  buyer2 uuid := '00000000-0000-0000-0000-00000000a905';
  p1 uuid := '00000000-0000-0000-0000-00000000a906';
  town_j smallint := (select id from public.towns where code = 'J');
  today_jkt date := (now() at time zone 'Asia/Jakarta')::date;
  ord_x uuid; ord_y uuid; inv1 uuid; inv2 uuid; payout uuid;
  n integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin9@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1p9@test.local', now(), now()),
    (agent1, 'authenticated', 'authenticated', 'agent1p9@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1p9@test.local', now(), now()),
    (buyer2, 'authenticated', 'authenticated', 'buyer2p9@test.local', now(), now());
  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000901', 'Admin Lengkap'),
    (dist1, 'distributor', '+6280000000902', 'Dist Lengkap'),
    (agent1, 'agent', '+6280000000903', 'Agen Lengkap'),
    (buyer1, 'buyer', '+6280000000904', 'Pembeli Satu'),
    (buyer2, 'buyer', '+6280000000905', 'Pembeli Dua');
  insert into public.agents (id, town_id) values (agent1, town_j);
  insert into public.buyers (id, business_name, business_type, town_id, agent_id) values
    (buyer1, 'Kios Lengkap', 'kios', town_j, agent1),
    (buyer2, 'Warung Lengkap', 'warung', town_j, null);
  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Lengkap', town_j, 'approved', now(), admin_id);
  insert into public.distributor_private (id, tax_number, bank_name, bank_account) values
    (dist1, 'TEST-TAX-P9', 'Bank Test', 'TEST-ACC-P9');
  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000);

  -- Order X by the agent for buyer1: confirmed and invoiced, then the invoice is paid
  perform pg_temp.as_user(agent1);
  ord_x := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 10)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_x, 'Accepted');
  perform public.transition_order(ord_x, 'Paid', null, 'PDC-J-0001');
  perform public.transition_order(ord_x, 'Shipped');
  perform pg_temp.as_user(buyer1);
  perform public.transition_order(ord_x, 'Confirmed');
  perform pg_temp.as_user(admin_id);
  perform public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
  select i.id into inv1 from public.invoices i where i.distributor_id = dist1;
  perform public.mark_invoice_paid(inv1, 'MUTASI-P9-1');

  -- Order Y by the agent: confirmed and invoiced, invoice left unpaid
  perform pg_temp.as_user(agent1);
  ord_y := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_y, 'Accepted');
  perform public.transition_order(ord_y, 'Paid', null, 'PDC-J-0002');
  perform public.transition_order(ord_y, 'Shipped');
  perform pg_temp.as_user(buyer1);
  perform public.transition_order(ord_y, 'Confirmed');
  perform pg_temp.as_user(admin_id);
  perform public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
  select i.id into inv2 from public.invoices i where i.distributor_id = dist1 and i.status = 'unpaid';

  -- 1. Suspension: a suspended buyer cannot place an order; reinstated, they can
  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_set_user_status(buyer2, 'suspended', '');
    insert into pg_temp.test_results values ('suspension needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('suspension needs a reason', true, sqlerrm);
  end;

  begin
    perform public.admin_set_user_status(admin_id, 'suspended', 'uji');
    insert into pg_temp.test_results values ('admin cannot suspend their own account', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('admin cannot suspend their own account', true, sqlerrm);
  end;

  perform public.admin_set_user_status(buyer2, 'suspended', 'Uji: penangguhan');
  perform pg_temp.as_user(buyer2);
  begin
    perform public.place_order(gen_random_uuid(), buyer2, dist1,
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('suspended buyer cannot place an order', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('suspended buyer cannot place an order', sqlerrm like '%suspended%', sqlerrm);
  end;

  perform pg_temp.as_user(admin_id);
  perform public.admin_set_user_status(buyer2, 'active', 'Uji: dipulihkan');
  perform pg_temp.as_user(buyer2);
  insert into pg_temp.test_results values ('reinstated buyer can place an order',
    (public.place_order(gen_random_uuid(), buyer2, dist1,
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)))) ? 'order_id', null);

  -- 2. Suspension also stops the agent's work (the agent acts for buyers)
  perform pg_temp.as_user(admin_id);
  perform public.admin_set_user_status(agent1, 'suspended', 'Uji: agen');
  perform pg_temp.as_user(agent1);
  begin
    perform public.sync_action(gen_random_uuid(), 'place_order', jsonb_build_object(
      'buyer_id', buyer1, 'distributor_id', dist1,
      'items', jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1))));
    insert into pg_temp.test_results values ('suspended agent cannot queue actions', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('suspended agent cannot queue actions', sqlerrm like '%suspended%', sqlerrm);
  end;
  perform pg_temp.as_user(admin_id);
  perform public.admin_set_user_status(agent1, 'active', 'Uji: selesai');

  -- 3. Agent payouts are refused until the agent fee is decided (D-008)
  begin
    perform public.generate_agent_payouts(to_char(today_jkt, 'YYYY-MM'));
    insert into pg_temp.test_results values ('payouts refused until D-008 is decided', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('payouts refused until D-008 is decided', sqlerrm like '%D-008%', sqlerrm);
  end;

  -- 4. Once decided, only orders with a paid invoice are paid out (order X, not Y)
  perform public.admin_set_config('agent_fee_per_order', '5000'::jsonb, 'Uji: biaya agen');
  n := public.generate_agent_payouts(to_char(today_jkt, 'YYYY-MM'));
  insert into pg_temp.test_results values ('payout is created for the paid order only',
    n = 1 and (select order_count = 1 and amount = 5000 from public.agent_payouts where agent_id = agent1 and period = to_char(today_jkt, 'YYYY-MM')),
    n::text);

  -- 5. Running again does not pay the same order twice
  n := public.generate_agent_payouts(to_char(today_jkt, 'YYYY-MM'));
  insert into pg_temp.test_results values ('running again pays nothing twice', n = 0, n::text);

  -- 6. Paying a payout needs a bank reference; once paid, it cannot be paid again
  select p.id into payout from public.agent_payouts p where p.agent_id = agent1;
  begin
    perform public.mark_agent_payout_paid(payout, '  ');
    insert into pg_temp.test_results values ('payout needs a bank reference', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('payout needs a bank reference', true, sqlerrm);
  end;
  perform public.mark_agent_payout_paid(payout, 'MUTASI-AGEN-1');
  insert into pg_temp.test_results values ('admin pays the payout; reference kept',
    (select status = 'paid' and reference = 'MUTASI-AGEN-1' from public.agent_payouts where id = payout), null);
  begin
    perform public.mark_agent_payout_paid(payout, 'MUTASI-AGEN-2');
    insert into pg_temp.test_results values ('payout cannot be paid twice', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('payout cannot be paid twice', true, sqlerrm);
  end;

  -- 7. The agent sees their own payout; another buyer sees none
  perform pg_temp.as_user(agent1);
  set local role authenticated;
  select count(*) into n from public.agent_payouts;
  reset role;
  insert into pg_temp.test_results values ('agent sees own payout', n = 1, n::text);

  perform pg_temp.as_user(buyer2);
  set local role authenticated;
  select count(*) into n from public.agent_payouts;
  reset role;
  insert into pg_temp.test_results values ('other users see no payouts', n = 0, n::text);

  -- 8. Scheduled daily job: overdue blocks skipped while D-007 is undecided; logged, not failed
  perform pg_temp.as_user(null);
  perform public.run_scheduled_jobs('daily');
  insert into pg_temp.test_results values ('daily job logs overdue blocks as skipped until D-007',
    exists (select 1 from public.job_runs where job = 'daily' and step = 'overdue_blocks' and status = 'skipped'), null);

  -- 9. Scheduled weekly job: invoices and the weekly KPI snapshot are run and logged
  perform public.run_scheduled_jobs('weekly');
  insert into pg_temp.test_results values ('weekly job logs invoices and KPI snapshot as ok',
    (select count(*) from public.job_runs where job = 'weekly' and status = 'ok') = 2, null);
  insert into pg_temp.test_results values ('weekly KPI snapshot stores all seven metrics',
    (select count(*) from public.kpi_snapshots where period_type = 'weekly') = 7,
    (select count(*)::text from public.kpi_snapshots where period_type = 'weekly'));

  -- 10. Snapshots and job logs are for admin only
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.kpi_snapshots;
  reset role;
  insert into pg_temp.test_results values ('buyer cannot read KPI snapshots', n = 0, n::text);

  begin
    perform public.run_scheduled_jobs('weekly');
    insert into pg_temp.test_results values ('buyer cannot run scheduled jobs', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot run scheduled jobs', true, sqlerrm);
  end;

  begin
    perform public.run_scheduled_jobs('hourly');
    insert into pg_temp.test_results values ('unknown job refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('unknown job refused', sqlerrm like '%Unknown job%', sqlerrm);
  end;

  -- 11. Non-admins cannot change account status
  begin
    perform public.admin_set_user_status(buyer1, 'suspended', 'uji');
    insert into pg_temp.test_results values ('buyer cannot change account status', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot change account status', true, sqlerrm);
  end;

  -- 12. The scheduler is set up: both jobs registered
  insert into pg_temp.test_results values ('scheduler has the daily and weekly jobs',
    (select count(*) from cron.job where jobname in ('mitralink-daily', 'mitralink-weekly')) = 2, null);

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 7 COMPLETION TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
