-- Phase 3: catalogue. Source: docs/product-spec.md section 4.2 (FR-06 to FR-08), BR-03, BR-08.
--
-- Catalogue changes go through functions only (products cannot be written directly).
-- Restricted goods are data: a category is restricted by its `restricted` flag, which
-- the founder and admin control (decision D-005). Admin can hide a listing with a reason.

-- Photo size, admin hide fields. Photo limit is 300 KB (FR-08).
alter table public.products
  add column photo_bytes integer check (photo_bytes is null or photo_bytes between 0 and 307200),
  add column hidden_reason text,
  add column hidden_at timestamptz,
  add column hidden_by uuid references auth.users (id),
  add constraint products_hidden_consistent check (
    ((hidden_reason is null) = (hidden_at is null))
    and ((hidden_reason is null) = (hidden_by is null))
  );

-- Read: own products; or admin; or any product from an approved, unblocked distributor
-- that admin has not hidden.
drop policy products_read on public.products;
drop policy products_owner_write on public.products;

create policy products_read on public.products for select to authenticated
  using (
    distributor_id = auth.uid()
    or public.is_admin()
    or (
      hidden_reason is null
      and exists (
        select 1 from public.distributors d
        where d.id = products.distributor_id
          and d.approval_status = 'approved'
          and d.blocked_at is null
      )
    )
  );

-- No direct writes. Only the functions below change products.
revoke insert, update, delete on public.products from anon, authenticated;

-- Shared field checks for add and update (FR-07, FR-08, BR-03).
create or replace function public._check_product_fields(
  p_distributor uuid,
  p_category_id text,
  p_name text,
  p_unit text,
  p_price integer,
  p_photo_path text,
  p_photo_bytes integer
)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Nama produk wajib diisi';
  end if;
  if p_unit is null or length(trim(p_unit)) = 0 then
    raise exception 'Satuan wajib diisi';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Harga tidak valid';
  end if;
  if not exists (select 1 from public.categories c where c.id = p_category_id) then
    raise exception 'Kategori tidak dikenal';
  end if;
  if exists (select 1 from public.categories c where c.id = p_category_id and c.restricted) then
    raise exception 'Barang terlarang tidak boleh dijual (BR-03)';
  end if;
  if p_photo_path is not null and p_photo_path not like ('products/' || p_distributor::text || '/%') then
    raise exception 'Foto harus berada di folder distributor Anda';
  end if;
  if p_photo_bytes is not null and p_photo_bytes > 307200 then
    raise exception 'Foto harus kurang dari 300 KB (FR-08)';
  end if;
end;
$$;

-- Add a product (FR-08). Approved distributor only.
create or replace function public.add_product(
  p_category_id text,
  p_name text,
  p_unit text,
  p_price integer,
  p_photo_path text default null,
  p_photo_bytes integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
begin
  if v_actor is null or not exists (
    select 1 from public.distributors d where d.id = v_actor and d.approval_status = 'approved'
  ) then
    raise exception 'Only an approved distributor can add products' using errcode = '42501';
  end if;

  perform public._check_product_fields(v_actor, p_category_id, p_name, p_unit, p_price, p_photo_path, p_photo_bytes);

  insert into public.products (distributor_id, category_id, name, unit, price, photo_path, photo_bytes)
  values (v_actor, p_category_id, trim(p_name), trim(p_unit), p_price, p_photo_path, p_photo_bytes)
  returning id into v_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, 'distributor', 'product.added', 'product', v_id::text,
          jsonb_build_object('name', trim(p_name), 'price', p_price, 'category', p_category_id));

  return v_id;
end;
$$;

-- Update a product. Its owner or admin. Null arguments keep the current value.
create or replace function public.update_product(
  p_product_id uuid,
  p_category_id text default null,
  p_name text default null,
  p_unit text default null,
  p_price integer default null,
  p_photo_path text default null,
  p_photo_bytes integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_p public.products%rowtype;
  v_cat text;
  v_name text;
  v_unit text;
  v_price integer;
  v_path text;
  v_bytes integer;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  select * into v_p from public.products where id = p_product_id for update;
  if not found then
    raise exception 'Product not found';
  end if;
  if not (public.is_admin() or v_p.distributor_id = v_actor) then
    raise exception 'Not your product' using errcode = '42501';
  end if;

  v_cat := coalesce(p_category_id, v_p.category_id);
  v_name := coalesce(p_name, v_p.name);
  v_unit := coalesce(p_unit, v_p.unit);
  v_price := coalesce(p_price, v_p.price);
  v_path := coalesce(p_photo_path, v_p.photo_path);
  v_bytes := coalesce(p_photo_bytes, v_p.photo_bytes);

  perform public._check_product_fields(v_p.distributor_id, v_cat, v_name, v_unit, v_price, v_path, v_bytes);

  update public.products
     set category_id = v_cat,
         name = trim(v_name),
         unit = trim(v_unit),
         price = v_price,
         photo_path = v_path,
         photo_bytes = v_bytes,
         updated_at = now()
   where id = p_product_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, case when public.is_admin() then 'admin' else 'distributor' end,
          'product.updated', 'product', p_product_id::text,
          jsonb_build_object('price', v_p.price, 'available', v_p.available),
          jsonb_build_object('price', v_price));
end;
$$;

-- Show or hide a product to buyers (FR-06). An admin-hidden product cannot be shown again by the distributor.
create or replace function public.set_product_availability(p_product_id uuid, p_available boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_p public.products%rowtype;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  select * into v_p from public.products where id = p_product_id for update;
  if not found then
    raise exception 'Product not found';
  end if;
  if not (public.is_admin() or v_p.distributor_id = v_actor) then
    raise exception 'Not your product' using errcode = '42501';
  end if;
  if p_available and v_p.hidden_reason is not null then
    raise exception 'This product was hidden by admin and cannot be shown again by the distributor';
  end if;

  update public.products set available = p_available, updated_at = now() where id = p_product_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, case when public.is_admin() then 'admin' else 'distributor' end,
          'product.availability', 'product', p_product_id::text,
          jsonb_build_object('available', v_p.available),
          jsonb_build_object('available', p_available));
end;
$$;

-- Admin hides a listing with a reason (FR-07). Stays hidden until admin unhides it.
create or replace function public.admin_hide_product(p_product_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can hide products' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to hide a product';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id) then
    raise exception 'Product not found';
  end if;

  update public.products
     set hidden_reason = trim(p_reason),
         hidden_at = now(),
         hidden_by = v_actor,
         available = false,
         updated_at = now()
   where id = p_product_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, 'admin', 'product.hidden', 'product', p_product_id::text,
          jsonb_build_object('reason', trim(p_reason)));
end;
$$;

-- Admin unhides a listing. It stays unavailable until the distributor shows it again.
create or replace function public.admin_unhide_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can unhide products' using errcode = '42501';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.hidden_reason is not null) then
    raise exception 'Product is not hidden';
  end if;

  update public.products
     set hidden_reason = null, hidden_at = null, hidden_by = null, updated_at = now()
   where id = p_product_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id)
  values (v_actor, 'admin', 'product.unhidden', 'product', p_product_id::text);
end;
$$;

-- Catalogue for buyers in a town (FR-06). Runs with the caller's rights, so RLS applies:
-- only approved, unblocked, unhidden listings from approved distributors show up.
-- Restricted categories are never returned.
create or replace function public.browse_catalogue(p_town_code text, p_category_id text default null)
returns table (
  product_id uuid,
  distributor_id uuid,
  distributor_name text,
  category_id text,
  category_name text,
  product_name text,
  unit text,
  price integer,
  available boolean,
  photo_path text
)
language sql
stable
security invoker
set search_path = public
as $$
  select p.id, d.id, d.business_name, c.id, c.name, p.name, p.unit, p.price, p.available, p.photo_path
    from public.products p
    join public.distributors d on d.id = p.distributor_id
    join public.towns t on t.id = d.town_id
    join public.categories c on c.id = p.category_id
   where t.code = p_town_code
     and c.restricted = false
     and (p_category_id is null or p.category_id = p_category_id)
   order by d.business_name, p.name
$$;

-- Function access. Supabase grants anon by default, so revoke it explicitly.
revoke execute on function public._check_product_fields(uuid, text, text, text, integer, text, integer)
  from public, anon, authenticated, service_role;
revoke execute on function public.add_product(text, text, text, integer, text, integer) from public, anon;
revoke execute on function public.update_product(uuid, text, text, text, integer, text, integer) from public, anon;
revoke execute on function public.set_product_availability(uuid, boolean) from public, anon;
revoke execute on function public.admin_hide_product(uuid, text) from public, anon;
revoke execute on function public.admin_unhide_product(uuid) from public, anon;
revoke execute on function public.browse_catalogue(text, text) from public, anon;

grant execute on function public.add_product(text, text, text, integer, text, integer) to authenticated, service_role;
grant execute on function public.update_product(uuid, text, text, text, integer, text, integer) to authenticated, service_role;
grant execute on function public.set_product_availability(uuid, boolean) to authenticated, service_role;
grant execute on function public.admin_hide_product(uuid, text) to authenticated, service_role;
grant execute on function public.admin_unhide_product(uuid) to authenticated, service_role;
grant execute on function public.browse_catalogue(text, text) to authenticated, service_role;
