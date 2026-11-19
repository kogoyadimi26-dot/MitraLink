-- Phase 2 onboarding test: registration, agent town rule, distributor approval, visibility.
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
  admin_id uuid := '00000000-0000-0000-0000-00000000d001';
  newbuyer uuid := '00000000-0000-0000-0000-00000000d002';
  newagent uuid := '00000000-0000-0000-0000-00000000d003';
  newdist uuid := '00000000-0000-0000-0000-00000000d004';
  dist2 uuid := '00000000-0000-0000-0000-00000000d005';
  buyer3 uuid := '00000000-0000-0000-0000-00000000d006';
  buyer4 uuid := '00000000-0000-0000-0000-00000000d007';
  agent2 uuid := '00000000-0000-0000-0000-00000000d008';
  res uuid;
  n integer;
  v_text text;
  fails integer;
begin
  insert into auth.users (id, aud, role, email, created_at, updated_at) values
    (admin_id, 'authenticated', 'authenticated', 'admin2@test.local', now(), now()),
    (newbuyer, 'authenticated', 'authenticated', 'newbuyer@test.local', now(), now()),
    (newagent, 'authenticated', 'authenticated', 'newagent@test.local', now(), now()),
    (newdist, 'authenticated', 'authenticated', 'newdist@test.local', now(), now()),
    (dist2, 'authenticated', 'authenticated', 'dist2@test.local', now(), now()),
    (buyer3, 'authenticated', 'authenticated', 'buyer3@test.local', now(), now()),
    (buyer4, 'authenticated', 'authenticated', 'buyer4@test.local', now(), now()),
    (agent2, 'authenticated', 'authenticated', 'agent2@test.local', now(), now());

  insert into public.profiles (id, role, phone, full_name) values
    (admin_id, 'admin', '+6280000000101', 'Admin Phase 2');

  -- 1. Admin creates an agent in Jayapura
  perform pg_temp.as_user(admin_id);
  res := public.create_agent(newagent, '+6280000000103', 'Pak Agen', 'J');
  insert into pg_temp.test_results values ('admin creates agent in Jayapura',
    (select town_id = (select id from public.towns where code = 'J') from public.agents where id = newagent), res::text);

  -- 2. A non-admin cannot create an agent
  perform pg_temp.as_user(newagent);
  begin
    perform public.create_agent(agent2, '+6280000000108', 'Agen Dua', 'J');
    insert into pg_temp.test_results values ('agent cannot create agents', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('agent cannot create agents', true, sqlerrm);
  end;

  -- 3. Buyer registers themselves
  perform pg_temp.as_user(newbuyer);
  res := public.register_buyer(newbuyer, '+6280000000102', 'Ibu Ani', 'Kios Ani', 'kios', 'J', 'v1');
  insert into pg_temp.test_results values ('buyer registers themselves; no agent; terms recorded',
    (select agent_id is null from public.buyers where id = newbuyer)
    and (select terms_version = 'v1' and terms_accepted_at is not null from public.profiles where id = newbuyer),
    res::text);

  -- 4. Duplicate phone is refused with the Bahasa Indonesia message
  perform pg_temp.as_user(buyer3);
  begin
    perform public.register_buyer(buyer3, '+6280000000102', 'Orang Lain', 'Warung Dua', 'warung', 'J', 'v1');
    insert into pg_temp.test_results values ('duplicate phone refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('duplicate phone refused', sqlerrm = 'Nomor ini sudah terdaftar', sqlerrm);
  end;

  -- 5. A buyer cannot register someone else's account
  perform pg_temp.as_user(newbuyer);
  begin
    perform public.register_buyer(buyer3, '+6280000000113', 'Orang Tiga', 'Warung Tiga', 'warung', 'J', 'v1');
    insert into pg_temp.test_results values ('buyer cannot register another account', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('buyer cannot register another account', true, sqlerrm);
  end;

  -- 6. Agent registers a buyer in their own town; the buyer is linked to the agent
  perform pg_temp.as_user(newagent);
  res := public.register_buyer(buyer3, '+6280000000113', 'Pak Tiga', 'Warung Tiga', 'warung', 'J', 'v1');
  insert into pg_temp.test_results values ('agent registers buyer in own town; linked to agent',
    (select agent_id = newagent from public.buyers where id = buyer3), res::text);

  -- 7. Agent cannot register a buyer in another town
  perform pg_temp.as_user(newagent);
  begin
    perform public.register_buyer(buyer4, '+6280000000114', 'Pak Empat', 'Toko Empat', 'kios', 'W', 'v1');
    insert into pg_temp.test_results values ('agent cannot register buyer in another town', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('agent cannot register buyer in another town', true, sqlerrm);
  end;

  -- 8. Terms must be accepted
  perform pg_temp.as_user(buyer4);
  begin
    perform public.register_buyer(buyer4, '+6280000000114', 'Pak Empat', 'Toko Empat', 'kios', 'J', null);
    insert into pg_temp.test_results values ('registration requires accepted terms', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('registration requires accepted terms', true, sqlerrm);
  end;

  -- 9. Town must be open for registration
  begin
    perform public.register_buyer(buyer4, '+6280000000114', 'Pak Empat', 'Toko Empat', 'kios', 'XX', 'v1');
    insert into pg_temp.test_results values ('unknown town refused', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('unknown town refused', true, sqlerrm);
  end;

  -- 10. Distributor registers themselves; account starts pending
  perform pg_temp.as_user(newdist);
  res := public.register_distributor(newdist, '+6280000000115', 'Pak Dist', 'CV Baru', 'J',
    'TEST-TAX-NEW', 'Bank Test', 'TEST-ACC-NEW', 'v1');
  insert into pg_temp.test_results values ('distributor registers; status pending',
    (select approval_status = 'pending' from public.distributors where id = newdist), res::text);

  -- 11. Distributor cannot register for another account
  begin
    perform public.register_distributor(dist2, '+6280000000116', 'Orang', 'CV Lain', 'J', null, null, 'TEST-ACC-X', 'v1');
    insert into pg_temp.test_results values ('distributor cannot register another account', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot register another account', true, sqlerrm);
  end;

  -- 12. A pending distributor cannot approve themselves
  begin
    perform public.approve_distributor(newdist, 'c1');
    insert into pg_temp.test_results values ('distributor cannot approve themselves', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('distributor cannot approve themselves', true, sqlerrm);
  end;

  -- 13. Approval needs the commission terms version
  perform pg_temp.as_user(admin_id);
  begin
    perform public.approve_distributor(newdist, '');
    insert into pg_temp.test_results values ('approval needs commission terms version', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('approval needs commission terms version', true, sqlerrm);
  end;

  -- 14. Admin approves; approver and terms are recorded; audit row written
  perform public.approve_distributor(newdist, 'c1');
  insert into pg_temp.test_results values ('admin approves distributor; approver, terms and audit recorded',
    (select approval_status = 'approved' and approved_by = admin_id and commission_terms_version = 'c1' and approved_at is not null
       from public.distributors where id = newdist)
    and exists (select 1 from public.audit_log where action = 'distributor.approved' and entity_id = newdist::text),
    null);

  -- 15. Second distributor registers, then rejection needs a reason
  perform pg_temp.as_user(dist2);
  perform public.register_distributor(dist2, '+6280000000116', 'Pak Dua', 'CV Dua', 'J', null, 'Bank Test', 'TEST-ACC-2', 'v1');
  perform pg_temp.as_user(admin_id);
  begin
    perform public.reject_distributor(dist2, '');
    insert into pg_temp.test_results values ('rejection needs a reason', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('rejection needs a reason', true, sqlerrm);
  end;

  -- 16. Admin rejects with a reason; reason is kept
  perform public.reject_distributor(dist2, 'Dokumen NIB belum lengkap');
  insert into pg_temp.test_results values ('admin rejects with reason kept',
    (select approval_status = 'rejected' and rejection_reason = 'Dokumen NIB belum lengkap' from public.distributors where id = dist2), null);

  -- 17. Approved distributor is visible to buyers (name and status only)
  perform pg_temp.as_user(buyer3);
  set local role authenticated;
  select count(*) into n from public.distributors where id = newdist;
  reset role;
  insert into pg_temp.test_results values ('buyer sees approved distributor', n = 1, n::text);

  -- 18. Rejected distributor is not visible to buyers
  set local role authenticated;
  select count(*) into n from public.distributors where id = dist2;
  reset role;
  insert into pg_temp.test_results values ('buyer does not see rejected distributor', n = 0, n::text);

  -- 19. Buyer cannot read the distributor's bank details
  set local role authenticated;
  select count(*) into n from public.distributor_private where id = newdist;
  reset role;
  insert into pg_temp.test_results values ('buyer cannot read distributor bank details', n = 0, n::text);

  -- 20. Distributor adds a document for themselves; a buyer cannot add one for them
  perform pg_temp.as_user(newdist);
  set local role authenticated;
  begin
    insert into public.distributor_documents (distributor_id, doc_type, storage_path, uploaded_by)
      values (newdist, 'NIB', 'docs/newdist/nib.pdf', newdist);
    reset role;
    insert into pg_temp.test_results values ('distributor uploads own document', true, null);
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('distributor uploads own document', false, sqlerrm);
  end;

  perform pg_temp.as_user(buyer3);
  set local role authenticated;
  begin
    insert into public.distributor_documents (distributor_id, doc_type, storage_path, uploaded_by)
      values (newdist, 'NIB', 'docs/fake.pdf', buyer3);
    reset role;
    insert into pg_temp.test_results values ('buyer cannot add document for a distributor', false, 'accepted');
  exception when others then
    reset role;
    insert into pg_temp.test_results values ('buyer cannot add document for a distributor', true, sqlerrm);
  end;

  -- 21. Phone numbers stay unique across account types (agent creation)
  perform pg_temp.as_user(admin_id);
  begin
    perform public.create_agent(agent2, '+6280000000115', 'Agen Dua', 'J');
    insert into pg_temp.test_results values ('agent creation refuses a used phone number', false, 'accepted');
  exception when others then
    insert into pg_temp.test_results values ('agent creation refuses a used phone number', true, sqlerrm);
  end;

  select count(*) filter (where not ok) into fails from pg_temp.test_results;
  select string_agg(name || ' => ' || case when ok then 'PASS' else 'FAIL' end || ' | ' || coalesce(detail, ''), E'\n' order by name)
    into v_text from pg_temp.test_results;
  raise exception E'PHASE 2 TEST RUN: % failing of % checks (all data rolled back)\n%',
    fails, (select count(*) from pg_temp.test_results), v_text;
end $test$;
