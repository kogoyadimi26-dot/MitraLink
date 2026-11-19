-- Business functions: order placement, order transitions, commission, guards and triggers.
-- Source: docs/product-spec.md sections 3, 8, 9; docs/business-requirements.md BR-02 to BR-13.
-- These functions are the only way orders change state (BR-13, FR-13).

-- Order code: PDC-<TOWN>-<NNNN>. Atomic per-town counter.
create or replace function public.next_order_code(p_town_id smallint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
  v_town_code text;
begin
  update public.town_sequences
     set last_seq = last_seq + 1
   where town_id = p_town_id
  returning last_seq into v_seq;

  if v_seq is null then
    raise exception 'No order sequence for town %', p_town_id;
  end if;

  select t.code into v_town_code from public.towns t where t.id = p_town_id;
  return format('PDC-%s-%s', v_town_code, lpad(v_seq::text, 4, '0'));
end;
$$;

-- Commission (FR-17, BR-02, BR-03, BR-04). Mirrors packages/shared/src/commission.ts:
-- lines are grouped by category, each category is rounded half up, the category
-- commissions are summed, and the minimum is applied once to the order total.
-- Writes commission_lines only. The caller sets the order's commission fields.
create or replace function public.calculate_order_commission(p_order_id uuid)
returns table (commission integer, minimum_applied boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_minimum integer;
  v_subtotal integer;
begin
  select (c.value #>> '{}')::integer
    into v_minimum
    from public.config c
   where c.key = 'minimum_commission';

  if v_minimum is null then
    raise exception 'minimum_commission is not configured (BR-02)';
  end if;

  delete from public.commission_lines cl where cl.order_id = p_order_id;

  insert into public.commission_lines (order_id, category_id, rate_bp, basis_amount, commission_amount)
  select
    i.order_id,
    c.id,
    c.rate_bp,
    sum(i.line_total)::integer,
    ((sum(i.line_total) * c.rate_bp + 5000) / 10000)::integer
  from public.order_items i
  join public.categories c on c.id = i.category_id
  where i.order_id = p_order_id
    and c.restricted = false
  group by i.order_id, c.id, c.rate_bp;

  select coalesce(sum(cl.commission_amount), 0)::integer
    into v_subtotal
    from public.commission_lines cl
   where cl.order_id = p_order_id;

  commission := greatest(v_subtotal, v_minimum);
  minimum_applied := commission <> v_subtotal;
  return next;
end;
$$;

-- Place an order for one distributor (FR-09, FR-23).
-- Idempotent on p_client_id: a retry returns the same order (NFR-03).
create or replace function public.place_order(
  p_client_id uuid,
  p_buyer_id uuid,
  p_distributor_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role public.user_role;
  v_buyer public.buyers%rowtype;
  v_dist public.distributors%rowtype;
  v_existing public.orders%rowtype;
  v_product public.products%rowtype;
  v_item jsonb;
  v_qty integer;
  v_order_id uuid;
  v_code text;
  v_subtotal integer := 0;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  v_role := public.current_role_name();

  -- Retry of a request that already succeeded: return the same order to its creator.
  select * into v_existing from public.orders where client_id = p_client_id;
  if found then
    if v_existing.created_by <> v_actor then
      raise exception 'Client id already used' using errcode = '23505';
    end if;
    return jsonb_build_object(
      'order_id', v_existing.id, 'code', v_existing.code,
      'state', v_existing.state, 'duplicate', true
    );
  end if;

  select * into v_buyer from public.buyers where id = p_buyer_id;
  if not found then
    raise exception 'Buyer not found';
  end if;

  -- Only the buyer, the buyer's agent, or admin may place this order.
  -- The agent test must be written so that a NULL agent_id gives false, not NULL.
  -- A NULL result would let "IF NOT (...)" pass silently (found by the DB test run).
  if not (
    v_actor = v_buyer.id
    or (v_buyer.agent_id is not null and v_actor = v_buyer.agent_id)
    or public.is_admin()
  ) then
    raise exception 'Not allowed to order for this buyer' using errcode = '42501';
  end if;

  select * into v_dist from public.distributors where id = p_distributor_id;
  if not found or v_dist.approval_status <> 'approved' then
    raise exception 'Distributor is not approved';
  end if;
  if v_dist.blocked_at is not null then
    raise exception 'Distributor is blocked for overdue invoices (BR-10)';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'An order needs at least one item';
  end if;

  v_code := public.next_order_code(v_buyer.town_id);

  insert into public.orders (code, client_id, buyer_id, agent_id, distributor_id, town_id, created_by)
  values (v_code, p_client_id, v_buyer.id, v_buyer.agent_id, v_dist.id, v_buyer.town_id, v_actor)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item ->> 'quantity')::integer;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantity must be a positive whole number';
    end if;

    select * into v_product from public.products where id = (v_item ->> 'product_id')::uuid;
    if not found or v_product.distributor_id <> v_dist.id then
      raise exception 'Product does not belong to this distributor';
    end if;
    if not v_product.available then
      raise exception 'Product % is not available', v_product.name;
    end if;

    insert into public.order_items (order_id, product_id, category_id, name_snapshot, unit_price, quantity, line_total)
    values (v_order_id, v_product.id, v_product.category_id, v_product.name,
            v_product.price, v_qty, v_product.price * v_qty);

    v_subtotal := v_subtotal + v_product.price * v_qty;
  end loop;

  update public.orders set subtotal = v_subtotal, updated_at = now() where id = v_order_id;

  insert into public.order_events (order_id, from_state, to_state, actor_user_id, actor_role, note)
  values (v_order_id, null, 'Placed', v_actor, v_role::text, 'Order placed');

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, v_role::text, 'order.placed', 'order', v_order_id::text,
          jsonb_build_object('code', v_code, 'subtotal', v_subtotal));

  return jsonb_build_object('order_id', v_order_id, 'code', v_code, 'state', 'Placed', 'duplicate', false);
end;
$$;

-- Move an order to a new state (FR-10 to FR-16, FR-09 to FR-14 transitions).
-- Actor is the signed-in user, or 'system' when called without a user (server jobs).
-- Checks the transition table, the actor's role, and that the actor owns the order.
create or replace function public.transition_order(
  p_order_id uuid,
  p_to public.order_state,
  p_client_id uuid default null,
  p_reference text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_order public.orders%rowtype;
  v_rule public.order_transitions%rowtype;
  v_replay public.client_actions%rowtype;
  v_result jsonb;
  v_conf_type text;
  v_comm integer;
  v_comm_min boolean;
begin
  if p_client_id is not null then
    select * into v_replay from public.client_actions where client_id = p_client_id;
    if found then
      if v_replay.actor_user_id is distinct from v_actor then
        raise exception 'Client id already used' using errcode = '23505';
      end if;
      return v_replay.result;
    end if;
  end if;

  v_actor_role := case when v_actor is null then 'system' else public.current_role_name()::text end;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found';
  end if;

  -- Ownership: buyers, agents and distributors act only on their own orders.
  if v_actor_role = 'buyer' and v_actor is distinct from v_order.buyer_id then
    raise exception 'Not your order' using errcode = '42501';
  end if;
  if v_actor_role = 'agent' and v_actor is distinct from v_order.agent_id then
    raise exception 'Not your order' using errcode = '42501';
  end if;
  if v_actor_role = 'distributor' and v_actor is distinct from v_order.distributor_id then
    raise exception 'Not your order' using errcode = '42501';
  end if;

  select * into v_rule from public.order_transitions
   where from_state = v_order.state and to_state = p_to;
  if not found then
    raise exception 'Transition from % to % is not allowed', v_order.state, p_to;
  end if;
  if not (v_actor_role = any (v_rule.allowed_actors)) then
    raise exception '% cannot move this order from % to %', v_actor_role, v_order.state, p_to
      using errcode = '42501';
  end if;

  -- Dispute resolution closes the open dispute (FR-15).
  if v_order.state = 'Disputed' then
    update public.disputes
       set status = 'resolved',
           resolution = coalesce(p_note, p_to::text),
           resolved_by = v_actor,
           resolved_at = now()
     where order_id = v_order.id and status = 'open';
  end if;

  if p_to = 'Accepted' then
    if exists (select 1 from public.distributors d where d.id = v_order.distributor_id and d.blocked_at is not null) then
      raise exception 'Distributor is blocked for overdue invoices (BR-10)';
    end if;
    update public.orders set accepted_at = now() where id = v_order.id;

  elsif p_to = 'Paid' then
    -- BR-05: payment must be recorded before shipping. The reference is the order code
    -- on the bank transfer, checked by the distributor against the bank statement.
    if p_reference is null or length(trim(p_reference)) = 0 then
      raise exception 'A payment reference is required (BR-05)';
    end if;
    insert into public.payments (order_id, reference, amount, marked_by)
    values (v_order.id, trim(p_reference), v_order.subtotal, v_actor);
    update public.orders set paid_at = now() where id = v_order.id;

  elsif p_to = 'Shipped' then
    insert into public.shipments (order_id, marked_by) values (v_order.id, v_actor);
    update public.orders set shipped_at = now() where id = v_order.id;

  elsif p_to = 'Disputed' then
    if p_note is null or length(trim(p_note)) = 0 then
      raise exception 'A dispute needs a reason (FR-15)';
    end if;
    insert into public.disputes (order_id, reason, created_by)
    values (v_order.id, trim(p_note), v_actor);

  elsif p_to = 'Confirmed' then
    v_conf_type := case
      when v_actor_role = 'system' then 'auto'
      when v_actor_role = 'buyer' then 'received'
      else 'dispute_resolved'
    end;
    insert into public.confirmations (order_id, type, confirmed_by)
    values (v_order.id, v_conf_type, v_actor);
    select c.commission, c.minimum_applied into v_comm, v_comm_min
      from public.calculate_order_commission(v_order.id) c;
  end if;

  -- One update sets the new state. Commission fields are set only with Confirmed,
  -- which the table constraint on orders requires.
  if p_to = 'Confirmed' then
    update public.orders
       set state = 'Confirmed',
           updated_at = now(),
           confirmed_at = now(),
           confirmation_type = v_conf_type,
           commission = v_comm,
           minimum_applied = v_comm_min
     where id = v_order.id;
  else
    update public.orders set state = p_to, updated_at = now() where id = v_order.id;
  end if;

  insert into public.order_events (order_id, from_state, to_state, actor_user_id, actor_role, note)
  values (v_order.id, v_order.state, p_to, v_actor, v_actor_role, p_note);

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (v_actor, v_actor_role, 'order.transition', 'order', v_order.id::text,
          jsonb_build_object('state', v_order.state),
          jsonb_build_object('state', p_to, 'commission', v_comm));

  v_result := jsonb_build_object('order_id', v_order.id, 'code', v_order.code, 'state', p_to);

  if p_client_id is not null then
    insert into public.client_actions (client_id, actor_user_id, action, entity_id, result)
    values (p_client_id, v_actor, 'order.transition', v_order.id::text, v_result);
  end if;

  return v_result;
end;
$$;

-- Guard: restricted goods cannot be listed (BR-03, FR-07).
create or replace function public.products_restricted_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from public.categories c where c.id = new.category_id and c.restricted) then
    raise exception 'Restricted goods cannot be listed (BR-03)';
  end if;
  return new;
end;
$$;

create trigger products_restricted_guard
  before insert or update of category_id on public.products
  for each row execute function public.products_restricted_guard();

-- Config audit: every change keeps the previous value and is logged (FR-26).
create or replace function public.config_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.previous_value := case when tg_op = 'UPDATE' then old.value else null end;
  new.changed_by := auth.uid();
  new.changed_at := now();

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
  values (
    auth.uid(),
    coalesce(public.current_role_name()::text, 'system'),
    'config.' || lower(tg_op),
    'config',
    new.key,
    case when tg_op = 'UPDATE' then jsonb_build_object('value', old.value) end,
    jsonb_build_object('value', new.value, 'reason', new.reason)
  );
  return new;
end;
$$;

create trigger config_audit
  before insert or update on public.config
  for each row execute function public.config_audit();

-- Client may call these. Everything else stays internal.
revoke execute on function public.next_order_code(smallint) from public, anon, authenticated, service_role;
revoke execute on function public.calculate_order_commission(uuid) from public, anon, authenticated, service_role;
revoke execute on function public.products_restricted_guard() from public, anon, authenticated, service_role;
revoke execute on function public.config_audit() from public, anon, authenticated, service_role;

-- Supabase grants new functions to anon by default. Take that back explicitly.
-- (Found by the security advisor after the first apply.)
revoke execute on function public.place_order(uuid, uuid, uuid, jsonb) from public, anon;
revoke execute on function public.transition_order(uuid, public.order_state, uuid, text, text) from public, anon;

grant execute on function public.place_order(uuid, uuid, uuid, jsonb) to authenticated, service_role;
grant execute on function public.transition_order(uuid, public.order_state, uuid, text, text) to authenticated, service_role;
