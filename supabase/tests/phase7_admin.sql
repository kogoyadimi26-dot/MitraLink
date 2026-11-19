-- Phase 7 admin test: configuration (validated, reasons, audited), category change audit,
-- KPI report against known data, audit viewer, admin block and unblock of a distributor.
-- Run against a development project only. Everything is rolled back: the script ends by
-- raising an error that carries the results. Expected output: "0 failing".

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
  admin_id uuid := '00000000-0000-0000-0000-00000000a801';
  dist1 uuid := '00000000-0000-0000-0000-00000000a802';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a803';
  p1 uuid := '00000000-0000-0000-0000-00000000a804';
  town_j smallint := (select id from public.towns where code = 'J');
  today_jkt date := (now() at time zone 'Asia/Jakarta')::date;
  ord_x uuid; ord_y uuid;
  res jsonb;
  n integer;
  v_val numeric;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin8@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1p8@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1p8@test.local', now(), now());
  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000801', 'Admin Laporan'),
    (dist1, 'distributor', '+6280000000802', 'Dist Laporan'),
    (buyer1, 'buyer', '+6280000000803', 'Pembeli Laporan');
  insert into public.buyers (id, business_name, business_type, town_id) values
    (buyer1, 'Kios Laporan', 'kios', town_j);
  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Laporan', town_j, 'approved', now(), admin_id);
  insert into public.distributor_private (id, tax_number, bank_name, bank_account) values
    (dist1, 'TEST-TAX-P8', 'Bank Test', 'TEST-ACC-P8');
  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000);

  -- Two orders: X is confirmed by the buyer at once; Y is disputed after shipping
  perform pg_temp.as_user(buyer1);
  ord_x := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 10)))->>'order_id')::uuid;
  ord_y := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_x, 'Accepted');
  perform public.transition_order(ord_x, 'Paid', null, 'PDC-J-0001');
  perform public.transition_order(ord_x, 'Shipped');
  perform public.transition_order(ord_y, 'Accepted');
  perform public.transition_order(ord_y, 'Paid', null, 'PDC-J-0002');
  perform public.transition_order(ord_y, 'Shipped');
  perform pg_temp.as_user(buyer1);
  perform public.transition_order(ord_x, 'Confirmed');
  perform public.transition_order(ord_y, 'Disputed', null, null, 'Karung rusak');

  -- 1. Admin changes a configured value; reason kept; audited
  perform pg_temp.as_user(admin_id);
  perform public.admin_set_config('invoice_due_days', '14'::jsonb, 'Uji: ubah masa jatuh tempo');
  insert into pg_temp.test_results values ('admin changes a configured value; reason kept; audited',
    (select value = '14'::jsonb and reason = 'Uji: ubah masa jatuh tempo' from public.config where key = 'invoice_due_days')
    and exists (select 1 from public.audit_log where entity = 'config' and entity_id = 'invoice_due_days' and action = 'config.update'),
    null);

  -- 2. A buyer cannot change configuration
  perform pg_temp.as_user(buyer1);
  begin
    perform public.admin_set_config('invoice_due_days', '10'::jsonb, 'x');
    insert into pg_temp.test_results values ('buyer cannot change configuration', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot change configuration', true, sqlerrm);
  end;

  -- 3. A reason is required
  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_set_config('invoice_due_days', '10'::jsonb, '');
    insert into pg_temp.test_results values ('configuration change needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('configuration change needs a reason', true, sqlerrm);
  end;

  -- 4. Out-of-range values, unknown keys and non-numbers are refused
  begin
    perform public.admin_set_config('invoice_due_days', '0'::jsonb, 'uji');
    insert into pg_temp.test_results values ('out-of-range value refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('out-of-range value refused', true, sqlerrm);
  end;

  begin
    perform public.admin_set_config('payment_window_days', '3'::jsonb, 'uji');
    insert into pg_temp.test_results values ('unknown configuration key refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('unknown configuration key refused', sqlerrm like '%Unknown configuration key%', sqlerrm);
  end;

  begin
    perform public.admin_set_config('invoice_due_days', '"tujuh"'::jsonb, 'uji');
    insert into pg_temp.test_results values ('non-number value refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('non-number value refused', true, sqlerrm);
  end;

  -- 5. A category rate change is audited
  update public.categories set rate_bp = 200 where id = 'staples';
  insert into pg_temp.test_results values ('category rate change is audited',
    exists (select 1 from public.audit_log where action = 'category.updated' and entity_id = 'staples'), null);

  -- 6. KPI report: 2 orders in 3 days = 4.7 per week; 1 buyer ordering; 1 of 2 shipped confirmed on time
  select r.value into v_val from public.kpi_report(today_jkt - 1, today_jkt + 1) r where r.metric = 'orders_per_week';
  insert into pg_temp.test_results values ('KPI: orders per week is 4.7', v_val = 4.7, v_val::text);

  select r.value into v_val from public.kpi_report(today_jkt - 1, today_jkt + 1) r where r.metric = 'buyers_ordering';
  insert into pg_temp.test_results values ('KPI: 1 buyer ordering', v_val = 1, v_val::text);

  select r.value into v_val from public.kpi_report(today_jkt - 1, today_jkt + 1) r where r.metric = 'on_time_confirmation_pct';
  insert into pg_temp.test_results values ('KPI: on-time confirmation is 50 percent (1 of 2 shipped)', v_val = 50, v_val::text);

  select r.value into v_val from public.kpi_report(today_jkt - 1, today_jkt + 1) r where r.metric = 'dispute_rate_pct';
  insert into pg_temp.test_results values ('KPI: dispute rate is 50 percent (1 of 2 shipped)', v_val = 50, v_val::text);

  select r.value into v_val from public.kpi_report(today_jkt - 1, today_jkt + 1) r where r.metric = 'invoices_paid_on_time_pct';
  insert into pg_temp.test_results values ('KPI: invoice figure is empty with no invoices', v_val is null, coalesce(v_val::text, 'null'));

  -- 7. Reports are admin only; an invalid period is refused
  perform pg_temp.as_user(buyer1);
  begin
    perform * from public.kpi_report(today_jkt - 1, today_jkt + 1);
    insert into pg_temp.test_results values ('buyer cannot view KPI reports', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot view KPI reports', true, sqlerrm);
  end;

  perform pg_temp.as_user(admin_id);
  begin
    perform * from public.kpi_report(today_jkt + 1, today_jkt - 1);
    insert into pg_temp.test_results values ('invalid KPI period refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('invalid KPI period refused', true, sqlerrm);
  end;

  -- 8. Audit viewer: filtered by order, capped page size; not for buyers
  select count(*) into n from public.admin_search_audit('order', ord_x::text);
  insert into pg_temp.test_results values ('audit viewer shows the history of an order', n >= 4, n::text);

  select count(*) into n from public.admin_search_audit('order', ord_x::text, null, null, null, 1);
  insert into pg_temp.test_results values ('audit viewer respects the page size', n = 1, n::text);

  perform pg_temp.as_user(buyer1);
  begin
    perform * from public.admin_search_audit('order', ord_x::text);
    insert into pg_temp.test_results values ('buyer cannot read the audit log', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot read the audit log', true, sqlerrm);
  end;

  -- 9. Admin blocks a distributor (suspension): no new orders; lifting restores them
  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_set_distributor_block(dist1, true, '');
    insert into pg_temp.test_results values ('block needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('block needs a reason', true, sqlerrm);
  end;

  perform public.admin_set_distributor_block(dist1, true, 'Uji: penangguhan');
  perform pg_temp.as_user(buyer1);
  begin
    perform public.place_order(gen_random_uuid(), buyer1, dist1,
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('admin-blocked distributor takes no orders', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('admin-blocked distributor takes no orders', sqlerrm like '%blocked%', sqlerrm);
  end;

  perform pg_temp.as_user(admin_id);
  perform public.admin_set_distributor_block(dist1, false, 'Uji: selesai');
  perform pg_temp.as_user(buyer1);
  res := public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
  insert into pg_temp.test_results values ('lifting the block restores ordering', res ? 'order_id', res::text);

  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_set_distributor_block(dist1, false, 'uji');
    insert into pg_temp.test_results values ('cannot lift a block that is not set', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('cannot lift a block that is not set', true, sqlerrm);
  end;

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 7 TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
