-- Database rules test: order path, transitions, commission, guards, audit, and RLS.
-- Run against a development project only. Everything is inside one transaction and
-- the script ends by raising an error that carries the results, so all test data is
-- rolled back and nothing is kept. Source: docs/product-spec.md sections 3, 6, 8; BR-02 to BR-13.
--
-- How to run: paste into the SQL editor of a DEV project, or run with psql against a
-- dev database. Expected output: "0 failing of 31 checks".

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
  admin_id uuid := '00000000-0000-0000-0000-00000000a001';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a002';
  agent1 uuid := '00000000-0000-0000-0000-00000000a003';
  dist1 uuid := '00000000-0000-0000-0000-00000000a004';
  buyer2 uuid := '00000000-0000-0000-0000-00000000a005';
  dist2 uuid := '00000000-0000-0000-0000-00000000a006';
  p1 uuid := '00000000-0000-0000-0000-00000000b001';
  p2 uuid := '00000000-0000-0000-0000-00000000b002';
  town_j smallint := (select id from public.towns where code = 'J');
  town_w smallint := (select id from public.towns where code = 'W');
  order1 uuid;
  order2 uuid;
  res jsonb;
  n integer;
  v_text text;
  fails integer;
  cl_count integer;
  client1 uuid := '00000000-0000-0000-0000-00000000c001';
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1@test.local', now(), now()),
    (agent1, 'authenticated', 'authenticated', 'agent1@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1@test.local', now(), now()),
    (buyer2, 'authenticated', 'authenticated', 'buyer2@test.local', now(), now()),
    (dist2, 'authenticated', 'authenticated', 'dist2@test.local', now(), now());

  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000001', 'Admin Test'),
    (buyer1, 'buyer', '+6280000000002', 'Buyer One'),
    (agent1, 'agent', '+6280000000003', 'Agent One'),
    (dist1, 'distributor', '+6280000000004', 'Distributor One'),
    (buyer2, 'buyer', '+6280000000005', 'Buyer Two'),
    (dist2, 'distributor', '+6280000000006', 'Distributor Pending');

  insert into public.agents (id, town_id) values (agent1, town_j);
  insert into public.buyers (id, business_name, business_type, town_id, agent_id) values
    (buyer1, 'Kios Maju Jaya', 'kios', town_j, agent1),
    (buyer2, 'Warung Kita', 'warung', town_w, null);

  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Papua Sejahtera', town_j, 'approved', now(), admin_id),
    (dist2, 'CV Belum Disetujui', town_j, 'pending', null, null);
  insert into public.distributor_private (id, tax_number, bank_name, bank_account) values
    (dist1, 'TEST-TAX-0001', 'Bank Test', 'TEST-ACC-0001');

  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000),
    (p2, dist1, 'electronics_tools', 'Kipas angin', 'unit', 500000);

  -- Ordering and idempotency
  perform pg_temp.as_user(agent1);
  res := public.place_order(client1, buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 10),
                      jsonb_build_object('product_id', p2, 'quantity', 1)));
  order1 := (res->>'order_id')::uuid;
  insert into pg_temp.test_results values ('agent places order: subtotal 650000 and state Placed',
    (select subtotal = 650000 and state = 'Placed' from public.orders where id = order1), res::text);

  res := public.place_order(client1, buyer1, dist1, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
  insert into pg_temp.test_results values ('retry with same client id is idempotent',
    (res->>'order_id')::uuid = order1 and (res->>'duplicate')::boolean, res::text);

  begin
    perform public.place_order(gen_random_uuid(), buyer2, dist1, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('agent cannot order for another agent''s buyer', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('agent cannot order for another agent''s buyer', true, sqlerrm);
  end;

  begin
    perform public.place_order(gen_random_uuid(), buyer1, dist2, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('cannot order from unapproved distributor', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('cannot order from unapproved distributor', true, sqlerrm);
  end;

  insert into pg_temp.test_results values ('order code is PDC-J-0001',
    (select code = 'PDC-J-0001' from public.orders where id = order1), (select code from public.orders where id = order1));

  -- Transitions and actor rules
  perform pg_temp.as_user(buyer1);
  begin
    perform public.transition_order(order1, 'Accepted');
    insert into pg_temp.test_results values ('buyer cannot accept an order', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot accept an order', true, sqlerrm);
  end;

  perform pg_temp.as_user(dist1);
  res := public.transition_order(order1, 'Accepted');
  insert into pg_temp.test_results values ('distributor accepts; order moves on to AwaitingPayment',
    res->>'state' = 'AwaitingPayment', res::text);

  perform pg_temp.as_user(dist1);
  begin
    perform public.transition_order(order1, 'Shipped');
    insert into pg_temp.test_results values ('cannot ship before payment (scenario 4)', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('cannot ship before payment (scenario 4)', true, sqlerrm);
  end;

  perform pg_temp.as_user(buyer1);
  begin
    perform public.transition_order(order1, 'Paid', null, 'PDC-J-0001');
    insert into pg_temp.test_results values ('buyer cannot mark PAID', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot mark PAID', true, sqlerrm);
  end;

  perform pg_temp.as_user(dist1);
  begin
    perform public.transition_order(order1, 'Paid', null, '  ');
    insert into pg_temp.test_results values ('PAID requires a payment reference', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('PAID requires a payment reference', true, sqlerrm);
  end;

  res := public.transition_order(order1, 'Paid', null, 'PDC-J-0001');
  insert into pg_temp.test_results values ('distributor marks PAID; payment amount is 650000',
    res->>'state' = 'Paid' and (select amount from public.payments where order_id = order1) = 650000, res::text);

  res := public.transition_order(order1, 'Shipped');
  insert into pg_temp.test_results values ('distributor ships after payment', res->>'state' = 'Shipped', res::text);

  begin
    perform public.transition_order(order1, 'Confirmed');
    insert into pg_temp.test_results values ('distributor cannot confirm receipt', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot confirm receipt', true, sqlerrm);
  end;

  perform pg_temp.as_user(buyer2);
  begin
    perform public.transition_order(order1, 'Confirmed');
    insert into pg_temp.test_results values ('other buyer cannot confirm receipt', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('other buyer cannot confirm receipt', true, sqlerrm);
  end;

  -- Confirmation and commission
  perform pg_temp.as_user(buyer1);
  res := public.transition_order(order1, 'Confirmed');
  insert into pg_temp.test_results values ('buyer confirms; commission 25000 with minimum applied',
    res->>'state' = 'Confirmed'
    and (select commission = 25000 and minimum_applied from public.orders where id = order1), res::text);

  select count(*) into cl_count from public.commission_lines where order_id = order1
     and ((category_id = 'staples' and commission_amount = 2250) or (category_id = 'electronics_tools' and commission_amount = 10000));
  insert into pg_temp.test_results values ('commission lines: staples 2250 and electronics 10000', cl_count = 2, cl_count::text);

  insert into pg_temp.test_results values ('order events recorded (6)',
    (select count(*) from public.order_events where order_id = order1) = 6,
    (select count(*)::text from public.order_events where order_id = order1));

  insert into pg_temp.test_results values ('audit log has placed and transition rows',
    (select count(*) from public.audit_log where entity_id = order1::text) = 6,
    (select count(*)::text from public.audit_log where entity_id = order1::text));

  -- Restricted goods guard (BR-03): a restricted product cannot be inserted
  perform pg_temp.as_user(dist1);
  begin
    insert into public.products (distributor_id, category_id, name, unit, price)
      values (dist1, 'restricted', 'Test', 'unit', 1000);
    insert into pg_temp.test_results values ('restricted product cannot be listed', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('restricted product cannot be listed', true, sqlerrm);
  end;

  -- Blocked distributor (BR-10)
  perform pg_temp.as_user(admin_id);
  update public.distributors set blocked_at = now(), block_reason = 'test' where id = dist1;
  perform pg_temp.as_user(agent1);
  begin
    perform public.place_order(gen_random_uuid(), buyer1, dist1, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)));
    insert into pg_temp.test_results values ('blocked distributor refuses new orders', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('blocked distributor refuses new orders', true, sqlerrm);
  end;
  perform pg_temp.as_user(admin_id);
  update public.distributors set blocked_at = null, block_reason = null where id = dist1;

  -- Dispute path (FR-15) resolved by admin
  perform pg_temp.as_user(agent1);
  res := public.place_order(gen_random_uuid(), buyer1, dist1, jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 2)));
  order2 := (res->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(order2, 'Accepted');
  perform pg_temp.as_user(dist1);
  perform public.transition_order(order2, 'Paid', null, 'PDC-J-0002');
  perform public.transition_order(order2, 'Shipped');
  perform pg_temp.as_user(buyer1);
  begin
    perform public.transition_order(order2, 'Disputed', null, null, '');
    insert into pg_temp.test_results values ('dispute needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('dispute needs a reason', true, sqlerrm);
  end;
  res := public.transition_order(order2, 'Disputed', null, null, 'Barang rusak');
  insert into pg_temp.test_results values ('buyer raises dispute; order Disputed and dispute open',
    res->>'state' = 'Disputed' and (select status from public.disputes where order_id = order2) = 'open', res::text);
  perform pg_temp.as_user(dist1);
  begin
    perform public.transition_order(order2, 'Confirmed');
    insert into pg_temp.test_results values ('distributor cannot resolve dispute', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot resolve dispute', true, sqlerrm);
  end;
  perform pg_temp.as_user(admin_id);
  res := public.transition_order(order2, 'Confirmed', null, null, 'Diselesaikan: ganti barang');
  insert into pg_temp.test_results values ('admin resolves dispute to Confirmed with dispute_resolved type',
    res->>'state' = 'Confirmed'
    and (select confirmation_type from public.orders where id = order2) = 'dispute_resolved'
    and (select status from public.disputes where order_id = order2) = 'resolved', res::text);

  -- Configuration audit (FR-26)
  update public.config set value = '30000'::jsonb, reason = 'test change' where key = 'minimum_commission';
  insert into pg_temp.test_results values ('config change keeps previous value and is audited',
    (select previous_value = '25000'::jsonb from public.config where key = 'minimum_commission')
    and exists (select 1 from public.audit_log where entity = 'config' and action = 'config.update'),
    (select value::text from public.config where key = 'minimum_commission'));

  -- Row-level security (NFR-06), queried as the signed-in role
  perform pg_temp.as_user(buyer2);
  set local role authenticated;
  select count(*) into n from public.orders;
  reset role;
  insert into pg_temp.test_results values ('RLS: other buyer sees 0 orders', n = 0, n::text);

  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.orders;
  reset role;
  insert into pg_temp.test_results values ('RLS: buyer sees their own 2 orders', n = 2, n::text);

  perform pg_temp.as_user(dist2);
  set local role authenticated;
  select count(*) into n from public.orders;
  reset role;
  insert into pg_temp.test_results values ('RLS: pending distributor sees 0 orders', n = 0, n::text);

  perform pg_temp.as_user(dist1);
  set local role authenticated;
  select count(*) into n from public.distributor_private;
  reset role;
  insert into pg_temp.test_results values ('RLS: distributor sees own bank details (1 row)', n = 1, n::text);

  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.distributor_private;
  reset role;
  insert into pg_temp.test_results values ('RLS: buyer cannot read distributor bank details', n = 0, n::text);

  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  begin
    insert into public.orders (code, client_id, buyer_id, distributor_id, town_id, created_by)
      values ('PDC-J-9999', gen_random_uuid(), buyer1, dist1, town_j, buyer1);
    reset role;
    insert into pg_temp.test_results values ('RLS: buyer cannot insert orders directly', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('RLS: buyer cannot insert orders directly', true, sqlerrm);
  end;

  -- Report. The raise rolls back every change made above.
  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
