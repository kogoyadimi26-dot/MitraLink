-- Phase 3 catalogue test: adding and changing products, restricted goods, photo limits,
-- browsing by town, admin hide and unhide, and ordering a hidden product.
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
  admin_id uuid := '00000000-0000-0000-0000-00000000e001';
  dist1 uuid := '00000000-0000-0000-0000-00000000e002';
  dist2 uuid := '00000000-0000-0000-0000-00000000e003';
  dist3 uuid := '00000000-0000-0000-0000-00000000e004';
  buyer1 uuid := '00000000-0000-0000-0000-00000000e005';
  p_beras uuid := '00000000-0000-0000-0000-00000000f001';
  p_gula uuid := '00000000-0000-0000-0000-00000000f002';
  p_w uuid := '00000000-0000-0000-0000-00000000f003';
  town_j smallint := (select id from public.towns where code = 'J');
  town_w smallint := (select id from public.towns where code = 'W');
  new_prod uuid;
  n integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin3@test.local', now(), now()),
    (dist1, 'authenticated', 'authenticated', 'dist1c@test.local', now(), now()),
    (dist2, 'authenticated', 'authenticated', 'dist2c@test.local', now(), now()),
    (dist3, 'authenticated', 'authenticated', 'dist3c@test.local', now(), now()),
    (buyer1, 'authenticated', 'authenticated', 'buyer1c@test.local', now(), now());

  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000201', 'Admin Katalog'),
    (dist1, 'distributor', '+6280000000202', 'Dist Jayapura'),
    (dist2, 'distributor', '+6280000000203', 'Dist Pending'),
    (dist3, 'distributor', '+6280000000204', 'Dist Wamena'),
    (buyer1, 'buyer', '+6280000000205', 'Pembeli Katalog');

  insert into public.distributors (id, business_name, town_id, approval_status, approved_at, approved_by) values
    (dist1, 'CV Jayapura Katalog', town_j, 'approved', now(), admin_id),
    (dist2, 'CV Belum Katalog', town_j, 'pending', null, null),
    (dist3, 'CV Wamena Katalog', town_w, 'approved', now(), admin_id);

  insert into public.buyers (id, business_name, business_type, town_id) values
    (buyer1, 'Kios Katalog', 'kios', town_j);

  insert into public.products (id, distributor_id, category_id, name, unit, price, available) values
    (p_beras, dist1, 'staples', 'Beras 25kg', 'karung', 15000, true),
    (p_gula, dist1, 'staples', 'Gula pasir', 'kg', 16000, false),
    (p_w, dist3, 'staples', 'Beras Wamena', 'karung', 15500, true);
  insert into public.products (distributor_id, category_id, name, unit, price)
    values (dist1, 'staples', 'Minyak goreng', 'liter', 18000);

  -- 1. Approved distributor adds a product
  perform pg_temp.as_user(dist1);
  new_prod := public.add_product('staples', 'Minyak goreng 2L', 'botol', 35000, null, null);
  insert into pg_temp.test_results values ('approved distributor adds a product',
    (select distributor_id = dist1 and available from public.products where id = new_prod), new_prod::text);

  -- 2. Restricted goods cannot be added (BR-03)
  begin
    perform public.add_product('restricted', 'Barang terlarang', 'unit', 1000, null, null);
    insert into pg_temp.test_results values ('restricted goods refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('restricted goods refused', true, sqlerrm);
  end;

  -- 3. Photo over 300 KB is refused (FR-08)
  begin
    perform public.add_product('staples', 'Foto besar', 'kg', 1000, 'products/' || dist1::text || '/besar.jpg', 400000);
    insert into pg_temp.test_results values ('photo over 300 KB refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('photo over 300 KB refused', true, sqlerrm);
  end;

  -- 4. Photo under the limit is accepted
  new_prod := public.add_product('staples', 'Foto kecil', 'kg', 1000, 'products/' || dist1::text || '/kecil.jpg', 200000);
  insert into pg_temp.test_results values ('photo under 300 KB accepted',
    (select photo_bytes = 200000 from public.products where id = new_prod), new_prod::text);

  -- 5. Photo must sit in the distributor's own folder
  begin
    perform public.add_product('staples', 'Foto orang lain', 'kg', 1000, 'products/' || dist3::text || '/x.jpg', 1000);
    insert into pg_temp.test_results values ('photo in another distributor folder refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('photo in another distributor folder refused', true, sqlerrm);
  end;

  -- 6. Negative price is refused
  begin
    perform public.add_product('staples', 'Harga minus', 'kg', -1, null, null);
    insert into pg_temp.test_results values ('negative price refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('negative price refused', true, sqlerrm);
  end;

  -- 7. Pending distributor cannot add products
  perform pg_temp.as_user(dist2);
  begin
    perform public.add_product('staples', 'Produk pending', 'kg', 1000, null, null);
    insert into pg_temp.test_results values ('pending distributor cannot add products', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('pending distributor cannot add products', true, sqlerrm);
  end;

  -- 8. Buyer cannot add products
  perform pg_temp.as_user(buyer1);
  begin
    perform public.add_product('staples', 'Produk pembeli', 'kg', 1000, null, null);
    insert into pg_temp.test_results values ('buyer cannot add products', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot add products', true, sqlerrm);
  end;

  -- 9. No direct inserts into products (functions only)
  perform pg_temp.as_user(dist1);
  set local role authenticated;
  begin
    insert into public.products (distributor_id, category_id, name, unit, price)
      values (dist1, 'staples', 'Langsung', 'kg', 1000);
    reset role;
    insert into pg_temp.test_results values ('direct insert into products refused', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('direct insert into products refused', true, sqlerrm);
  end;

  -- 10. Buyer browses Jayapura: approved town products, unavailable ones shown greyed (available = false),
  --     and nothing from Wamena or from a pending distributor
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.browse_catalogue('J');
  reset role;
  insert into pg_temp.test_results values ('buyer browse J shows the 5 Jayapura products', n = 5, n::text);

  set local role authenticated;
  select count(*) into n from public.browse_catalogue('J') b where b.product_id = p_gula and b.available = false;
  reset role;
  insert into pg_temp.test_results values ('unavailable product shows as not available', n = 1, n::text);

  -- 11. A distributor cannot change another distributor's product
  perform pg_temp.as_user(dist1);
  begin
    perform public.update_product(p_w, null, 'Ganti nama');
    insert into pg_temp.test_results values ('distributor cannot change another''s product', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot change another''s product', true, sqlerrm);
  end;

  -- 12. Owner updates a price; null arguments keep other fields
  perform public.update_product(p_gula, null, null, null, 17000, null, null);
  insert into pg_temp.test_results values ('owner updates price; name kept',
    (select price = 17000 and name = 'Gula pasir' from public.products where id = p_gula), null);

  -- 13. Owner shows and hides their product
  perform public.set_product_availability(p_beras, false);
  perform public.set_product_availability(p_beras, true);
  insert into pg_temp.test_results values ('owner toggles availability',
    (select available from public.products where id = p_beras), null);

  -- 14. Admin hide needs a reason
  perform pg_temp.as_user(admin_id);
  begin
    perform public.admin_hide_product(p_beras, '');
    insert into pg_temp.test_results values ('admin hide needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('admin hide needs a reason', true, sqlerrm);
  end;

  -- 15. Admin hides a listing; buyers no longer see it; the distributor still sees it in its own list
  perform public.admin_hide_product(p_beras, 'Label kemasan tidak sesuai');
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.browse_catalogue('J');
  reset role;
  insert into pg_temp.test_results values ('hidden product gone from buyer catalogue', n = 4, n::text);

  perform pg_temp.as_user(dist1);
  set local role authenticated;
  select count(*) into n from public.products where id = p_beras;
  reset role;
  insert into pg_temp.test_results values ('distributor still sees own hidden product', n = 1, n::text);

  -- 16. The distributor cannot show a hidden product again
  begin
    perform public.set_product_availability(p_beras, true);
    insert into pg_temp.test_results values ('distributor cannot re-show hidden product', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot re-show hidden product', true, sqlerrm);
  end;

  -- 17. A buyer cannot order a hidden product
  perform pg_temp.as_user(buyer1);
  begin
    perform public.place_order(gen_random_uuid(), buyer1, dist1,
      jsonb_build_array(jsonb_build_object('product_id', p_beras, 'quantity', 1)));
    insert into pg_temp.test_results values ('buyer cannot order a hidden product', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot order a hidden product', true, sqlerrm);
  end;

  -- 18. Admin unhides; the product returns to the catalogue, still unavailable until the distributor shows it
  perform pg_temp.as_user(admin_id);
  perform public.admin_unhide_product(p_beras);
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.browse_catalogue('J') b where b.product_id = p_beras and b.available = false;
  reset role;
  insert into pg_temp.test_results values ('unhidden product back in catalogue, unavailable', n = 1, n::text);

  -- 19. A blocked distributor's products are hidden from the catalogue (BR-10)
  perform pg_temp.as_user(admin_id);
  update public.distributors set blocked_at = now(), block_reason = 'test' where id = dist3;
  perform pg_temp.as_user(buyer1);
  set local role authenticated;
  select count(*) into n from public.browse_catalogue('W');
  reset role;
  insert into pg_temp.test_results values ('blocked distributor products hidden from catalogue', n = 0, n::text);
  perform pg_temp.as_user(admin_id);
  update public.distributors set blocked_at = null, block_reason = null where id = dist3;

  -- 20. Admin hide cannot target a product that does not exist
  begin
    perform public.admin_hide_product('00000000-0000-0000-0000-0000000000ff', 'tidak ada');
    insert into pg_temp.test_results values ('hiding a missing product refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('hiding a missing product refused', true, sqlerrm);
  end;

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 3 TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
