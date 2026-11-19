-- Phase 6 invoice test: weekly invoices, no double billing, payment marking, overdue detection,
-- overdue block (refused until D-007 is decided, then applied and lifted), tax fields, and access.
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
  admin_id uuid := '00000000-0000-0000-0000-00000000a601';
  dist1 uuid := '00000000-0000-0000-0000-00000000a602';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a603';
  agent1 uuid := '00000000-0000-0000-0000-00000000a604';
  p1 uuid := '00000000-0000-0000-0000-00000000a605';
  town_j smallint := (select id from public.towns where code = 'J');
  today_jkt date := (now() at time zone 'Asia/Jakarta')::date;
  ord_x uuid; ord_y uuid; ord_z uuid;
  inv_xy uuid; inv_z uuid;
  res jsonb;
  n integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin6@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1p6@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1p6@test.local', now(), now()),
    (agent1, 'authenticated', 'authenticated', 'agent1p6@test.local', now(), now());

  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000601', 'Admin Faktur'),
    (dist1, 'distributor', '+6280000000602', 'Dist Faktur'),
    (buyer1, 'buyer', '+6280000000603', 'Pembeli Faktur'),
    (agent1, 'agent', '+6280000000604', 'Agen Faktur');
  insert into public.agents (id, town_id) values (agent1, town_j);
  insert into public.buyers (id, business_name, business_type, town_id, agent_id) values
    (buyer1, 'Kios Faktur', 'kios', town_j, agent1);
  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Faktur', town_j, 'approved', now(), admin_id);
  insert into public.distributor_private (id, tax_number, bank_name, bank_account) values
    (dist1, 'TEST-TAX-P6', 'Bank Test', 'TEST-ACC-P6');
  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000);

  -- Three confirmed orders, each with the Rp25,000 minimum commission
  perform pg_temp.as_user(agent1);
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
  perform public.transition_order(ord_y, 'Confirmed');

  -- 1. Weekly run creates one invoice for the distributor, covering both orders
  perform pg_temp.as_user(admin_id);
  n := public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
  insert into pg_temp.test_results values ('weekly run creates one invoice for the distributor', n = 1, n::text);

  select i.id into inv_xy from public.invoices i where i.distributor_id = dist1;

  -- 2. Total equals the commission on both orders; both orders linked; number format
  insert into pg_temp.test_results values ('invoice total is 50000 and links both orders',
    (select total_commission = 50000 from public.invoices where id = inv_xy)
    and (select count(*) from public.invoice_orders where invoice_id = inv_xy) = 2
    and (select number like 'MLK-%' from public.invoices where id = inv_xy),
    (select number from public.invoices where id = inv_xy));

  -- 3. Due date is 7 days after issue (config invoice_due_days)
  insert into pg_temp.test_results values ('due date is 7 days after issue',
    (select due_date = today_jkt + 7 from public.invoices where id = inv_xy), null);

  -- 4. Tax number recorded on the invoice (FR-20); no tax calculated
  insert into pg_temp.test_results values ('invoice records distributor tax number',
    (select distributor_tax_number = 'TEST-TAX-P6' from public.invoices where id = inv_xy), null);

  -- 5. Running again does not invoice the same orders twice
  n := public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
  insert into pg_temp.test_results values ('second run creates nothing for billed orders', n = 0, n::text);

  -- 6. Invalid period refused
  begin
    perform public.generate_weekly_invoices(today_jkt + 1, today_jkt - 1);
    insert into pg_temp.test_results values ('invalid period refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('invalid period refused', true, sqlerrm);
  end;

  -- 7. A buyer cannot generate invoices
  perform pg_temp.as_user(buyer1);
  begin
    perform public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
    insert into pg_temp.test_results values ('buyer cannot generate invoices', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot generate invoices', true, sqlerrm);
  end;

  -- 8. Mark paid needs a bank reference; admin marks paid; second mark refused
  perform pg_temp.as_user(admin_id);
  begin
    perform public.mark_invoice_paid(inv_xy, '  ');
    insert into pg_temp.test_results values ('mark paid needs a bank reference', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('mark paid needs a bank reference', true, sqlerrm);
  end;

  perform public.mark_invoice_paid(inv_xy, 'MUTASI-0001');
  insert into pg_temp.test_results values ('admin marks invoice paid with bank reference',
    (select status = 'paid' and paid_at is not null and bank_reference = 'MUTASI-0001' from public.invoices where id = inv_xy), null);

  begin
    perform public.mark_invoice_paid(inv_xy, 'MUTASI-0002');
    insert into pg_temp.test_results values ('invoice cannot be marked paid twice', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('invoice cannot be marked paid twice', true, sqlerrm);
  end;

  -- 9. Order Z: a third confirmed order, invoiced on its own
  perform pg_temp.as_user(agent1);
  ord_z := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 2)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_z, 'Accepted');
  perform public.transition_order(ord_z, 'Paid', null, 'PDC-J-0003');
  perform public.transition_order(ord_z, 'Shipped');
  perform pg_temp.as_user(buyer1);
  perform public.transition_order(ord_z, 'Confirmed');
  perform pg_temp.as_user(admin_id);
  n := public.generate_weekly_invoices(today_jkt - 1, today_jkt + 1);
  select i.id into inv_z from public.invoices i where i.distributor_id = dist1 and i.status = 'unpaid';
  insert into pg_temp.test_results values ('new confirmed order gets its own invoice', n = 1 and inv_z is not null, n::text);

  -- 10. Distributor cannot mark an invoice paid
  perform pg_temp.as_user(dist1);
  begin
    perform public.mark_invoice_paid(inv_z, 'MUTASI-DIST');
    insert into pg_temp.test_results values ('distributor cannot mark invoice paid', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot mark invoice paid', true, sqlerrm);
  end;

  -- 11. Make invoice Z 10 days overdue; overdue list shows it
  update public.invoices set due_date = today_jkt - 10 where id = inv_z;
  perform pg_temp.as_user(admin_id);
  select count(*) into n from public.overdue_invoices() o where o.invoice_id = inv_z and o.days_overdue = 10;
  insert into pg_temp.test_results values ('overdue list shows the invoice with 10 days overdue', n = 1, n::text);

  -- 12. Blocks are refused until the overdue block period is decided (D-007)
  begin
    perform public.apply_distributor_blocks();
    insert into pg_temp.test_results values ('blocks refused until D-007 is decided', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('blocks refused until D-007 is decided', sqlerrm like '%D-007%', sqlerrm);
  end;

  -- 13. Once decided (7 days), the overdue distributor is blocked; a blocked distributor takes no orders
  insert into public.config (key, value, reason) values ('overdue_block_days', '7'::jsonb, 'test: D-007 set');
  n := public.apply_distributor_blocks();
  insert into pg_temp.test_results values ('overdue distributor is blocked after the block period',
    n = 1 and (select blocked_at is not null and block_reason = 'Invoice overdue (BR-10)' from public.distributors where id = dist1),
    n::text);

  perform pg_temp.as_user(agent1);
  begin
    perform public.place_order(gen_random_uuid(), buyer1, dist1,
      jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('blocked distributor takes no new orders', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('blocked distributor takes no new orders', sqlerrm like '%blocked%', sqlerrm);
  end;

  -- 14. Paying the overdue invoice lifts the block
  perform pg_temp.as_user(admin_id);
  perform public.mark_invoice_paid(inv_z, 'MUTASI-0003');
  n := public.apply_distributor_blocks();
  insert into pg_temp.test_results values ('paying the invoice lifts the block',
    n = 1 and (select blocked_at is null from public.distributors where id = dist1), n::text);

  -- 15. Visibility: the distributor sees its invoices; a buyer sees none
  perform pg_temp.as_user(dist1);
  set local role authenticated;
  select count(*) into n from public.invoices;
  reset role;
  insert into pg_temp.test_results values ('distributor sees its own invoices', n = 2, n::text);

  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.invoices;
  reset role;
  insert into pg_temp.test_results values ('buyer sees no invoices', n = 0, n::text);

  -- 16. Invoices cannot be written directly
  perform pg_temp.as_user(admin_id);
  set local role authenticated;
  begin
    insert into public.invoices (number, distributor_id, period_start, period_end, total_commission, due_date)
      values ('MLK-FAKE-0001', dist1, today_jkt, today_jkt, 1, today_jkt);
    reset role;
    insert into pg_temp.test_results values ('invoices cannot be written directly', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('invoices cannot be written directly', true, sqlerrm);
  end;

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 6 INVOICE TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
