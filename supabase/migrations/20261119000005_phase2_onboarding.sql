-- Phase 2: identity and onboarding. Source: docs/product-spec.md section 4.1 (FR-01 to FR-05),
-- docs/business-requirements.md BR-12, BR-13, BR-14.
--
-- Scope of this migration: database functions and records. Phone sign-in (FR-01) needs
-- the SMS provider decision (D-001); the auth user is created by the sign-up flow, and
-- these functions need that auth user to exist already. Distributor document types (D-003)
-- are not enforced here: documents are recorded, and the approval checklist comes after the decision.

-- Rejection reason for distributors (FR-03).
alter table public.distributors add column rejection_reason text;

-- Documents uploaded by a distributor (FR-03). Storage path only, never the file itself.
create table public.distributor_documents (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors (id),
  doc_type text not null check (length(trim(doc_type)) > 0),
  storage_path text not null check (length(trim(storage_path)) > 0),
  uploaded_by uuid not null references auth.users (id),
  uploaded_at timestamptz not null default now()
);

alter table public.distributor_documents enable row level security;

-- The distributor sees and adds its own documents; admin sees all.
create policy distributor_documents_read on public.distributor_documents for select to authenticated
  using (distributor_id = auth.uid() or public.is_admin());
create policy distributor_documents_insert on public.distributor_documents for insert to authenticated
  with check (distributor_id = auth.uid() and uploaded_by = auth.uid());
create policy distributor_documents_admin on public.distributor_documents for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.distributor_documents from anon;

-- Register a buyer (FR-02). Callers:
--   the buyer registering themselves (p_user_id = their own auth id), or
--   an agent registering a buyer in the agent's own town (agent_id is set), or
--   admin.
create or replace function public.register_buyer(
  p_user_id uuid,
  p_phone text,
  p_full_name text,
  p_business_name text,
  p_business_type text,
  p_town_code text,
  p_terms_version text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role public.user_role := public.current_role_name();
  v_town smallint;
  v_agent_town smallint;
  v_agent_id uuid;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  if v_actor <> p_user_id and not public.is_admin() and v_role is distinct from 'agent' then
    raise exception 'Not allowed to register this buyer' using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'Sign-up is needed before registration';
  end if;
  if exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'This account is already registered';
  end if;
  if exists (select 1 from public.profiles p where p.phone = p_phone) then
    raise exception 'Nomor ini sudah terdaftar' using errcode = '23505';
  end if;
  if p_terms_version is null or length(trim(p_terms_version)) = 0 then
    raise exception 'Terms must be accepted before registration (FR-02)';
  end if;

  select t.id into v_town from public.towns t where t.code = p_town_code and t.active;
  if v_town is null then
    raise exception 'Town is not open for registration';
  end if;

  -- An agent may register buyers only in their own town, and the buyer is linked to that agent.
  if v_role = 'agent' and v_actor <> p_user_id then
    select a.town_id, a.id into v_agent_town, v_agent_id from public.agents a where a.id = v_actor;
    if v_agent_town is distinct from v_town then
      raise exception 'Agents can register buyers only in their own town';
    end if;
  end if;

  insert into public.profiles (id, role, phone, full_name, terms_version, terms_accepted_at)
  values (p_user_id, 'buyer', p_phone, p_full_name, p_terms_version, now());

  insert into public.buyers (id, business_name, business_type, town_id, agent_id)
  values (p_user_id, p_business_name, p_business_type, v_town, v_agent_id);

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, coalesce(v_role::text, 'system'), 'buyer.registered', 'buyer', p_user_id::text,
          jsonb_build_object('town', p_town_code, 'agent_id', v_agent_id));

  return p_user_id;
end;
$$;

-- Create an agent (FR-04). Admin only.
create or replace function public.create_agent(
  p_user_id uuid,
  p_phone text,
  p_full_name text,
  p_town_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_town smallint;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can create agents' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'Sign-up is needed before an agent account can be created';
  end if;
  if exists (select 1 from public.profiles p where p.id = p_user_id or p.phone = p_phone) then
    raise exception 'This account or phone number is already registered';
  end if;

  select t.id into v_town from public.towns t where t.code = p_town_code and t.active;
  if v_town is null then
    raise exception 'Town is not open for registration';
  end if;

  insert into public.profiles (id, role, phone, full_name)
  values (p_user_id, 'agent', p_phone, p_full_name);

  insert into public.agents (id, town_id) values (p_user_id, v_town);

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, 'admin', 'agent.created', 'agent', p_user_id::text,
          jsonb_build_object('town', p_town_code));

  return p_user_id;
end;
$$;

-- Register a distributor (FR-03). The distributor registers themselves; the account starts pending.
create or replace function public.register_distributor(
  p_user_id uuid,
  p_phone text,
  p_full_name text,
  p_business_name text,
  p_town_code text,
  p_tax_number text,
  p_bank_name text,
  p_bank_account text,
  p_terms_version text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_town smallint;
begin
  if v_actor is null or v_actor <> p_user_id then
    raise exception 'A distributor registers only for their own account' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'Sign-up is needed before registration';
  end if;
  if exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'This account is already registered';
  end if;
  if exists (select 1 from public.profiles p where p.phone = p_phone) then
    raise exception 'Nomor ini sudah terdaftar' using errcode = '23505';
  end if;
  if p_terms_version is null or length(trim(p_terms_version)) = 0 then
    raise exception 'Terms must be accepted before registration (FR-02)';
  end if;
  if p_bank_account is null or length(trim(p_bank_account)) = 0 then
    raise exception 'A bank account is needed to receive payments';
  end if;

  select t.id into v_town from public.towns t where t.code = p_town_code and t.active;
  if v_town is null then
    raise exception 'Town is not open for registration';
  end if;

  insert into public.profiles (id, role, phone, full_name, terms_version, terms_accepted_at)
  values (p_user_id, 'distributor', p_phone, p_full_name, p_terms_version, now());

  insert into public.distributors (id, business_name, town_id, approval_status)
  values (p_user_id, p_business_name, v_town, 'pending');

  insert into public.distributor_private (id, tax_number, bank_name, bank_account)
  values (p_user_id, p_tax_number, p_bank_name, p_bank_account);

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, 'distributor', 'distributor.registered', 'distributor', p_user_id::text,
          jsonb_build_object('town', p_town_code));

  return p_user_id;
end;
$$;

-- Approve a pending distributor (FR-03). Admin only. Records the commission terms version.
create or replace function public.approve_distributor(
  p_distributor_id uuid,
  p_commission_terms_version text
)
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
    raise exception 'Only admin can approve distributors' using errcode = '42501';
  end if;
  if p_commission_terms_version is null or length(trim(p_commission_terms_version)) = 0 then
    raise exception 'Commission terms version is required (BR-03)';
  end if;

  select d.approval_status into v_status from public.distributors d where d.id = p_distributor_id for update;
  if not found then
    raise exception 'Distributor not found';
  end if;
  if v_status <> 'pending' then
    raise exception 'Only a pending distributor can be approved (current: %)', v_status;
  end if;

  update public.distributors
     set approval_status = 'approved',
         approved_at = now(),
         approved_by = v_actor,
         commission_terms_version = p_commission_terms_version
   where id = p_distributor_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, 'admin', 'distributor.approved', 'distributor', p_distributor_id::text,
          jsonb_build_object('approval_status', v_status),
          jsonb_build_object('approval_status', 'approved', 'commission_terms_version', p_commission_terms_version));
end;
$$;

-- Reject a pending distributor (FR-03). Admin only. A reason is required and is kept.
create or replace function public.reject_distributor(
  p_distributor_id uuid,
  p_reason text
)
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
    raise exception 'Only admin can reject distributors' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to reject a distributor';
  end if;

  select d.approval_status into v_status from public.distributors d where d.id = p_distributor_id for update;
  if not found then
    raise exception 'Distributor not found';
  end if;
  if v_status <> 'pending' then
    raise exception 'Only a pending distributor can be rejected (current: %)', v_status;
  end if;

  update public.distributors
     set approval_status = 'rejected',
         rejection_reason = trim(p_reason)
   where id = p_distributor_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, 'admin', 'distributor.rejected', 'distributor', p_distributor_id::text,
          jsonb_build_object('approval_status', v_status),
          jsonb_build_object('approval_status', 'rejected', 'reason', trim(p_reason)));
end;
$$;

-- Function access: signed-in users and service role only. Supabase grants anon by default.
revoke execute on function public.register_buyer(uuid, text, text, text, text, text, text) from public, anon;
revoke execute on function public.create_agent(uuid, text, text, text) from public, anon;
revoke execute on function public.register_distributor(uuid, text, text, text, text, text, text, text, text) from public, anon;
revoke execute on function public.approve_distributor(uuid, text) from public, anon;
revoke execute on function public.reject_distributor(uuid, text) from public, anon;

grant execute on function public.register_buyer(uuid, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.create_agent(uuid, text, text, text) to authenticated, service_role;
grant execute on function public.register_distributor(uuid, text, text, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.approve_distributor(uuid, text) to authenticated, service_role;
grant execute on function public.reject_distributor(uuid, text) to authenticated, service_role;
