-- Phase 4 ordering test: decline, accept, payment instructions and proof, paid, shipped,
-- payment reversal, cancellation, disputes with photos, and notification queue.
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
  admin_id uuid := '00000000-0000-0000-0000-00000000a401';
  dist1 uuid := '00000000-0000-0000-0000-00000000a402';
  buyer1 uuid := '00000000-0000-0000-0000-00000000a403';
  agent1 uuid := '00000000-0000-0000-0000-00000000a404';
  buyer2 uuid := '00000000-0000-0000-0000-00000000a405';
  p1 uuid := '00000000-0000-0000-0000-00000000a501';
  town_j smallint := (select id from public.towns where code = 'J');
  ord_a uuid; ord_b uuid; ord_c uuid; ord_d uuid;
  res jsonb;
  n integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin4@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1p4@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1p4@test.local', now(), now()),
    (agent1, 'authenticated', 'authenticated', 'agent1p4@test.local', now(), now()),
    (buyer2, 'authenticated', 'authenticated', 'buyer2p4@test.local', now(), now());

  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000301', 'Admin Pesanan'),
    (dist1, 'distributor', '+6280000000302', 'Dist Pesanan'),
    (buyer1, 'buyer', '+6280000000303', 'Pembeli Satu'),
    (agent1, 'agent', '+6280000000304', 'Agen Pesanan'),
    (buyer2, 'buyer', '+6280000000305', 'Pembeli Dua');

  insert into public.agents (id, town_id) values (agent1, town_j);
  insert into public.buyers (id, business_name, business_type, town_id, agent_id) values
    (buyer1, 'Kios Pesanan', 'kios', town_j, agent1),
    (buyer2, 'Warung Pesanan', 'warung', town_j, null);
  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Pesanan', town_j, 'approved', now(), admin_id);
  insert into public.distributor_private (id, tax_number, bank_name, bank_account) values
    (dist1, 'TEST-TAX-P4', 'Bank Test', 'TEST-ACC-P4');
  insert into public.products (id, distributor_id, category_id, name, unit, price) values
    (p1, dist1, 'staples', 'Beras 25kg', 'karung', 15000);

  -- Agent places two orders for buyer1 (A to be accepted, B to be declined)
  perform pg_temp.as_user(agent1);
  ord_a := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 10)))->>'order_id')::uuid;
  ord_b := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 1)))->>'order_id')::uuid;

  -- 1. Placing an order queues notifications for the buyer and the distributor
  insert into pg_temp.test_results values ('placed order queues notifications for the buyer',
    (select count(*) from public.notifications where order_id = ord_a and recipient_id = buyer1 and template = 'order_placed') = 2,
    null);

  -- 2. A decline needs a reason
  perform pg_temp.as_user(dist1);
  begin
    perform public.transition_order(ord_b, 'Declined', null, null, '');
    insert into pg_temp.test_results values ('decline needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('decline needs a reason', true, sqlerrm);
  end;

  -- 3. Decline with a reason; reason kept; buyer notified
  res := public.transition_order(ord_b, 'Declined', null, null, 'Stok habis');
  insert into pg_temp.test_results values ('decline with reason; reason kept; buyer notified',
    res->>'state' = 'Declined'
    and (select decline_reason = 'Stok habis' from public.orders where id = ord_b)
    and exists (select 1 from public.notifications where order_id = ord_b and recipient_id = buyer1 and template = 'order_declined'),
    res::text);

  -- 4. Accept moves the order on to AwaitingPayment automatically; system event recorded
  res := public.transition_order(ord_a, 'Accepted');
  insert into pg_temp.test_results values ('accept moves order to AwaitingPayment automatically',
    res->>'state' = 'AwaitingPayment'
    and exists (select 1 from public.order_events where order_id = ord_a and to_state = 'AwaitingPayment' and actor_role = 'system')
    and exists (select 1 from public.notifications where order_id = ord_a and recipient_id = buyer1 and template = 'payment_needed'),
    res::text);

  -- 5. Buyer gets the bank details of the distributor; another buyer does not
  perform pg_temp.as_user(buyer1);
  select count(*) into n from public.get_payment_instructions(ord_a) i where i.bank_account = 'TEST-ACC-P4' and i.amount = 150000;
  insert into pg_temp.test_results values ('buyer gets payment instructions (bank, amount)', n = 1, n::text);

  perform pg_temp.as_user(buyer2);
  begin
    perform public.get_payment_instructions(ord_a);
    insert into pg_temp.test_results values ('other buyer cannot get payment instructions', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('other buyer cannot get payment instructions', true, sqlerrm);
  end;

  -- 6. Payment details are not shown for a declined order
  perform pg_temp.as_user(buyer1);
  begin
    perform public.get_payment_instructions(ord_b);
    insert into pg_temp.test_results values ('no payment details for a declined order', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('no payment details for a declined order', true, sqlerrm);
  end;

  -- 7. Proof photo: wrong folder refused, too large refused, right folder accepted
  begin
    perform public.attach_payment_proof(ord_a, 'payments/otherfolder/p.jpg', 1000);
    insert into pg_temp.test_results values ('proof in wrong folder refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('proof in wrong folder refused', true, sqlerrm);
  end;

  begin
    perform public.attach_payment_proof(ord_a, 'payments/' || ord_a::text || '/besar.jpg', 400000);
    insert into pg_temp.test_results values ('proof over 300 KB refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('proof over 300 KB refused', true, sqlerrm);
  end;

  perform public.attach_payment_proof(ord_a, 'payments/' || ord_a::text || '/p1.jpg', 200000);
  insert into pg_temp.test_results values ('buyer attaches transfer proof',
    (select count(*) from public.payment_proofs where order_id = ord_a) = 1, null);

  -- 8. Another buyer cannot attach proof to this order
  perform pg_temp.as_user(buyer2);
  begin
    perform public.attach_payment_proof(ord_a, 'payments/' || ord_a::text || '/x.jpg', 1000);
    insert into pg_temp.test_results values ('other buyer cannot attach proof', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('other buyer cannot attach proof', true, sqlerrm);
  end;

  -- 9. Distributor marks paid and ships; buyer notified at each step
  perform pg_temp.as_user(dist1);
  res := public.transition_order(ord_a, 'Paid', null, 'PDC-J-0001');
  perform public.transition_order(ord_a, 'Shipped');
  insert into pg_temp.test_results values ('paid and shipped; buyer notified of payment and shipment',
    (select state from public.orders where id = ord_a) = 'Shipped'
    and exists (select 1 from public.notifications where order_id = ord_a and template = 'payment_received')
    and exists (select 1 from public.notifications where order_id = ord_a and template = 'shipped'), null);

  -- 10. A payment cannot be reversed once the goods have shipped
  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_reverse_payment(ord_a, 'uji');
    insert into pg_temp.test_results values ('no payment reversal after shipping', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('no payment reversal after shipping', true, sqlerrm);
  end;

  -- 11. Order C: paid, then reversed by admin (reason needed); back to AwaitingPayment
  perform pg_temp.as_user(agent1);
  ord_c := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 2)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_c, 'Accepted');
  perform public.transition_order(ord_c, 'Paid', null, 'PDC-J-0003');

  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_reverse_payment(ord_c, '');
    insert into pg_temp.test_results values ('payment reversal needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('payment reversal needs a reason', true, sqlerrm);
  end;

  res := public.admin_reverse_payment(ord_c, 'Transfer salah rekening');
  insert into pg_temp.test_results values ('admin reverses payment; order back to AwaitingPayment; reason kept',
    res->>'state' = 'AwaitingPayment'
    and (select state from public.orders where id = ord_c) = 'AwaitingPayment'
    and exists (select 1 from public.payments where order_id = ord_c and reversed_at is not null
                and reversal_reason = 'Transfer salah rekening')
    and exists (select 1 from public.notifications where order_id = ord_c and template = 'payment_reversed'),
    res::text);

  -- 12. Cancellation needs a reason; admin cancels with a reason
  begin
    perform public.transition_order(ord_c, 'Cancelled', null, null, null);
    insert into pg_temp.test_results values ('cancellation needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('cancellation needs a reason', true, sqlerrm);
  end;

  res := public.transition_order(ord_c, 'Cancelled', null, null, 'Dibatalkan pembeli');
  insert into pg_temp.test_results values ('admin cancels with reason; reason kept',
    res->>'state' = 'Cancelled' and (select cancel_reason = 'Dibatalkan pembeli' from public.orders where id = ord_c),
    res::text);

  -- 13. Dispute with photos: buyer raises it after shipping; up to three photos
  perform pg_temp.as_user(agent1);
  ord_d := (public.place_order(gen_random_uuid(), buyer1, dist1,
    jsonb_build_array(jsonb_build_object('product_id', p1, 'quantity', 3)))->>'order_id')::uuid;
  perform pg_temp.as_user(dist1);
  perform public.transition_order(ord_d, 'Accepted');
  perform public.transition_order(ord_d, 'Paid', null, 'PDC-J-0004');
  perform public.transition_order(ord_d, 'Shipped');
  perform pg_temp.as_user(buyer1);
  res := public.transition_order(ord_d, 'Disputed', null, null, 'Karung rusak');
  insert into pg_temp.test_results values ('buyer raises dispute after shipping', res->>'state' = 'Disputed', res::text);

  begin
    perform public.add_dispute_photo(ord_d, 'disputes/otherfolder/1.jpg', 1000);
    insert into pg_temp.test_results values ('dispute photo in wrong folder refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('dispute photo in wrong folder refused', true, sqlerrm);
  end;

  perform public.add_dispute_photo(ord_d, 'disputes/' || ord_d::text || '/1.jpg', 100000);
  perform public.add_dispute_photo(ord_d, 'disputes/' || ord_d::text || '/2.jpg', 100000);
  perform public.add_dispute_photo(ord_d, 'disputes/' || ord_d::text || '/3.jpg', 100000);
  begin
    perform public.add_dispute_photo(ord_d, 'disputes/' || ord_d::text || '/4.jpg', 100000);
    insert into pg_temp.test_results values ('fourth dispute photo refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('fourth dispute photo refused', true, sqlerrm);
  end;

  -- 14. Notifications: the buyer reads their own; another buyer reads nothing of this order
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.notifications where order_id = ord_a;
  reset role;
  insert into pg_temp.test_results values ('buyer reads own notifications', n > 0, n::text);

  perform pg_temp.as_user(buyer2);
  set local role authenticated;
  select count(*) into n from public.notifications where order_id = ord_a;
  reset role;
  insert into pg_temp.test_results values ('other buyer reads no notifications of this order', n = 0, n::text);

  -- 15. Notifications cannot be written directly by users
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  begin
    insert into public.notifications (order_id, recipient_id, channel, template)
      values (ord_a, buyer1, 'sms', 'fake');
    reset role;
    insert into pg_temp.test_results values ('notifications cannot be written directly', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('notifications cannot be written directly', true, sqlerrm);
  end;

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 4 TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
