-- Phase 5 sync test: queued actions applied once, replays return the first result, conflicts and
-- rejections are reported (not applied silently), the sync log, and the PowerSync publication.
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
  admin_id uuid := '00000000-0000-0000-0000-00000000a701';
  dist1 uuid := '00000000-0000-0000-0000-00000000a702';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a703';
  buyer2 uuid := '00000000-0000-0000-0000-00000000a704';
  p1 uuid := '00000000-0000-0000-0000-00000000a705';
  town_j smallint := (select id from public.towns where code = 'J');
  c1 uuid := '00000000-0000-0000-0000-00000000c701';
  c2 uuid := '00000000-0000-0000-0000-00000000c702';
  c3 uuid := '00000000-0000-0000-0000-00000000c703';
  c4 uuid := '00000000-0000-0000-0000-00000000c704';
  c5 uuid := '00000000-0000-0000-0000-00000000c705';
  c6 uuid := '00000000-0000-0000-0000-00000000c706';
  ord uuid;
  ord_cancel uuid;
  res jsonb;
  n integer;
  events_before integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin7@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1p7@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1p7@test.local', now(), now()),
    (buyer2, 'authenticated', 'authenticated', 'buyer2p7@test.local', now(), now());
  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000701', 'Admin Sinkron'),
    (dist1, 'distributor', '+6280000000702', 'Dist Sinkron'),
    (buyer1, 'buyer', '+6280000000703', 'Pembeli Sinkron'),
    (buyer2, 'buyer', '+6280000000704', 'Pembeli Lain');
  insert into public.buyers (id, business_name, business_type, town_id) values
    (buyer1, 'Kios Sinkron', 'kios', town_j),
    (buyer2, 'Warung Lain', 'warung', town_j);
  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Sinkron', town_j, 'approved', now(), admin_id);
  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000);

  -- 1. A buyer's offline order is applied once
  perform pg_temp.as_user(buyer1);
  res := public.sync_action(c1, 'place_order', jsonb_build_object(
    'buyer_id', buyer1, 'distributor_id', dist1,
    'items', jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 2))));
  ord := (res->'result'->>'order_id')::uuid;
  insert into pg_temp.test_results values ('queued order is applied', res->>'status' = 'applied', res::text);

  -- 2. The same order sent again (retry) is a duplicate: one order only
  res := public.sync_action(c1, 'place_order', jsonb_build_object(
    'buyer_id', buyer1, 'distributor_id', dist1,
    'items', jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 2))));
  insert into pg_temp.test_results values ('retry is a duplicate; one order exists',
    res->>'status' = 'duplicate' and (select count(*) from public.orders where client_id = c1) = 1, res::text);

  -- 3. Distributor accepts (queued transition with a client id)
  perform pg_temp.as_user(dist1);
  res := public.sync_action(c2, 'transition', jsonb_build_object('order_id', ord, 'to', 'Accepted'));
  insert into pg_temp.test_results values ('queued accept is applied; order awaits payment',
    res->>'status' = 'applied' and (select state from public.orders where id = ord) = 'AwaitingPayment', res::text);

  -- 4. Buyer's queued RECEIVED arrives before payment: conflict, reported, nothing changed
  perform pg_temp.as_user(buyer1);
  res := public.sync_action(c3, 'transition', jsonb_build_object('order_id', ord, 'to', 'Confirmed'));
  insert into pg_temp.test_results values ('stale confirm is a conflict with reason; state unchanged',
    res->>'status' = 'conflict' and res->>'reason' is not null
    and (select state from public.orders where id = ord) = 'AwaitingPayment', res::text);

  -- 5. Another buyer's queued action is rejected (not their order)
  perform pg_temp.as_user(buyer2);
  res := public.sync_action(c4, 'transition', jsonb_build_object('order_id', ord, 'to', 'Confirmed'));
  insert into pg_temp.test_results values ('another buyer''s action is rejected',
    res->>'status' = 'rejected', res::text);

  -- 6. Admin cancels a second order; the buyer's queued confirm then conflicts, not silently applied
  perform pg_temp.as_user(buyer1);
  ord_cancel := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1))) ->> 'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_cancel, 'Accepted');
  perform pg_temp.as_user(admin_id);
  perform public.transition_order(ord_cancel, 'Cancelled', null, null, 'Stok tidak tersedia');
  perform pg_temp.as_user(buyer1);
  res := public.sync_action(c5, 'transition', jsonb_build_object('order_id', ord_cancel, 'to', 'Confirmed'));
  insert into pg_temp.test_results values ('confirm on a cancelled order is a conflict; no confirmation written',
    res->>'status' = 'conflict'
    and (select state from public.orders where id = ord_cancel) = 'Cancelled'
    and not exists (select 1 from public.confirmations where order_id = ord_cancel), res::text);

  -- 7. Unknown action is reported, not applied
  res := public.sync_action(c6, 'delete_everything', jsonb_build_object('x', 1));
  insert into pg_temp.test_results values ('unknown action is reported as a conflict',
    res->>'status' = 'conflict' and res->>'reason' like '%Unknown action%', res::text);

  -- 8. A replayed transition does not create a second event
  perform pg_temp.as_user(dist1);
  select count(*) into events_before from public.order_events where order_id = ord;
  res := public.sync_action(c2, 'transition', jsonb_build_object('order_id', ord, 'to', 'Accepted'));
  insert into pg_temp.test_results values ('replayed transition creates no new event',
    res->>'status' = 'duplicate' and (select count(*) from public.order_events where order_id = ord) = events_before, res::text);

  -- 9. Every processed action is logged once
  insert into pg_temp.test_results values ('sync log holds one row per processed client id',
    (select count(*) from public.sync_log where client_id in (c1, c2, c3, c4, c5, c6)) = 6,
    (select count(*)::text from public.sync_log where client_id in (c1, c2, c3, c4, c5, c6)));

  -- 10. Users read only their own sync log entries
  perform pg_temp.as_user(buyer2);
  set local role authenticated;
  select count(*) into n from public.sync_log where client_id in (c1, c2, c3, c4, c5, c6);
  reset role;
  insert into pg_temp.test_results values ('another user sees only their own sync log entry (c4)', n = 1, n::text);

  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.sync_log where client_id in (c1, c2, c3, c4, c5, c6);
  reset role;
  insert into pg_temp.test_results values ('the buyer reads their own sync log entries', n = 4, n::text);

  -- 11. Users cannot write the sync log directly
  set local role authenticated;
  begin
    insert into public.sync_log (client_id, actor_user_id, action, status)
      values (gen_random_uuid(), buyer1, 'x', 'applied');
    reset role;
    insert into pg_temp.test_results values ('sync log cannot be written directly', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('sync log cannot be written directly', true, sqlerrm);
  end;

  -- 12. Dispute photo for an order with no dispute is a conflict
  res := public.sync_action(gen_random_uuid(), 'dispute_photo', jsonb_build_object(
    'order_id', ord, 'path', 'disputes/' || ord::text || '/1.jpg', 'bytes', 1000));
  insert into pg_temp.test_results values ('dispute photo with no open dispute is a conflict',
    res->>'status' = 'conflict', res::text);

  -- 13. Payment proof for an order awaiting payment is applied
  res := public.sync_action(gen_random_uuid(), 'payment_proof', jsonb_build_object(
    'order_id', ord, 'path', 'payments/' || ord::text || '/bukti.jpg', 'bytes', 120000));
  insert into pg_temp.test_results values ('payment proof queued offline is applied',
    res->>'status' = 'applied', res::text);

  -- 14. The PowerSync publication carries orders, and not the bank details table
  insert into pg_temp.test_results values ('publication includes orders, excludes distributor_private',
    (select count(*) from pg_publication_tables where pubname = 'powersync' and tablename = 'orders') = 1
    and (select count(*) from pg_publication_tables where pubname = 'powersync' and tablename = 'distributor_private') = 0,
    null);

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 5 TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
