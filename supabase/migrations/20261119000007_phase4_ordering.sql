-- Phase 4: ordering and fulfilment. Source: docs/product-spec.md sections 3 and 4.3, 4.6
-- (FR-09 to FR-16, FR-23, FR-24), BR-05 to BR-07, BR-13.
--
-- Changes to the state machine (flagged for founder review in docs/product-spec.md):
--   1. Accepted moves to AwaitingPayment automatically, in the same call (the spec's
--      "system" step is done by the server, so the distributor does not need a second call).
--   2. Admin can reverse a payment: Paid goes back to AwaitingPayment (FR-12).
--   3. Declined and Cancelled need a reason, which is stored.
-- Notifications are queued here. Sending them (SMS, in-app) is the worker's job, and the
-- SMS provider is not chosen yet (D-001), so SMS messages stay queued.

-- Reasons for declined and cancelled orders (FR-10, FR-16).
alter table public.orders
  add column decline_reason text,
  add column cancel_reason text;

-- Admin may reverse a payment (FR-12). Allowed only from Paid.
insert into public.order_transitions (from_state, to_state, allowed_actors)
values ('Paid', 'AwaitingPayment', array['admin']);

-- Notification queue (FR-24). One row per recipient per channel. Written by trigger only.
create table public.notifications (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id),
  recipient_id uuid not null references auth.users (id),
  channel text not null check (channel in ('in_app', 'sms')),
  template text not null check (length(trim(template)) > 0),
  params jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  check ((status = 'sent') = (sent_at is not null))
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);
create index notifications_queue_idx on public.notifications (channel, status) where status = 'queued';

alter table public.notifications enable row level security;
create policy notifications_read on public.notifications for select to authenticated
  using (recipient_id = auth.uid() or public.is_admin());
revoke all on public.notifications from anon;
revoke insert, update, delete on public.notifications from authenticated;

-- Payment proof photos (FR-11). Not proof of payment on their own (BR-05).
create table public.payment_proofs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  storage_path text not null check (length(trim(storage_path)) > 0),
  bytes integer not null check (bytes between 1 and 307200),
  uploaded_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

alter table public.payment_proofs enable row level security;
create policy payment_proofs_read on public.payment_proofs for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.id = payment_proofs.order_id
        and (o.buyer_id = auth.uid() or o.agent_id = auth.uid() or o.distributor_id = auth.uid())
    )
  );
revoke all on public.payment_proofs from anon;
revoke insert, update, delete on public.payment_proofs from authenticated;

-- Queue notifications when an order event is written (FR-24). Templates are keys;
-- the app renders the Bahasa Indonesia text from strings/id.json.
create or replace function public.queue_order_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_recipients uuid[];
  v_template text;
  v_recipient uuid;
begin
  select * into v_order from public.orders where id = new.order_id;

  case new.to_state
    when 'Placed' then
      v_recipients := array[v_order.distributor_id, v_order.buyer_id, v_order.agent_id];
      v_template := 'order_placed';
    when 'Accepted' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id];
      v_template := 'order_accepted';
    when 'Declined' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id];
      v_template := 'order_declined';
    when 'AwaitingPayment' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id];
      v_template := 'payment_needed';
    when 'Paid' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id];
      v_template := 'payment_received';
    when 'Shipped' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id];
      v_template := 'shipped';
    when 'Confirmed' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id, v_order.distributor_id];
      v_template := 'confirmed';
    when 'Disputed' then
      v_recipients := array[v_order.distributor_id, v_order.agent_id];
      v_template := 'dispute_opened';
    when 'Cancelled' then
      v_recipients := array[v_order.buyer_id, v_order.agent_id, v_order.distributor_id];
      v_template := 'cancelled';
    else
      v_recipients := array[]::uuid[];
      v_template := null;
  end case;

  if new.from_state = 'Paid' and new.to_state = 'AwaitingPayment' then
    v_template := 'payment_reversed';
  end if;

  if v_template is null then
    return new;
  end if;

  foreach v_recipient in array v_recipients loop
    if v_recipient is not null then
      insert into public.notifications (order_id, recipient_id, channel, template, params)
      values (v_order.id, v_recipient, 'in_app', v_template,
              jsonb_build_object('code', v_order.code, 'state', new.to_state));
      insert into public.notifications (order_id, recipient_id, channel, template, params)
      values (v_order.id, v_recipient, 'sms', v_template,
              jsonb_build_object('code', v_order.code, 'state', new.to_state));
    end if;
  end loop;

  return new;
end;
$$;

create trigger order_events_notify
  after insert on public.order_events
  for each row execute function public.queue_order_notifications();

-- Payment instructions for the buyer: bank details of the distributor, only while payment is due or received.
create or replace function public.get_payment_instructions(p_order_id uuid)
returns table (
  order_code text,
  amount integer,
  bank_name text,
  bank_account text,
  distributor_name text,
  order_state public.order_state
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_o public.orders%rowtype;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  select * into v_o from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found';
  end if;
  if not (
    v_actor = v_o.buyer_id
    or (v_o.agent_id is not null and v_actor = v_o.agent_id)
    or public.is_admin()
  ) then
    raise exception 'Not your order' using errcode = '42501';
  end if;
  if v_o.state not in ('AwaitingPayment', 'Paid') then
    raise exception 'Payment details are shown only while payment is due or received';
  end if;

  return query
    select v_o.code, v_o.subtotal, pv.bank_name, pv.bank_account, d.business_name, v_o.state
      from public.distributor_private pv
      join public.distributors d on d.id = pv.id
     where pv.id = v_o.distributor_id;
end;
$$;

-- Buyer or agent attaches a transfer proof photo (FR-11). Stored path and size only.
create or replace function public.attach_payment_proof(p_order_id uuid, p_path text, p_bytes integer)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_o public.orders%rowtype;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  select * into v_o from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found';
  end if;
  if not (v_actor = v_o.buyer_id or (v_o.agent_id is not null and v_actor = v_o.agent_id)) then
    raise exception 'Not your order' using errcode = '42501';
  end if;
  if v_o.state not in ('AwaitingPayment', 'Paid') then
    raise exception 'Proof can be attached only while payment is due or received';
  end if;
  if p_path is null or p_path not like ('payments/' || p_order_id::text || '/%') then
    raise exception 'Proof must be stored in this order''s folder';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 307200 then
    raise exception 'Photo must be between 1 byte and 300 KB (FR-08)';
  end if;

  insert into public.payment_proofs (order_id, storage_path, bytes, uploaded_by)
  values (p_order_id, p_path, p_bytes, v_actor)
  returning id into v_id;

  insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, after)
  values (v_actor, case when v_actor = v_o.buyer_id then 'buyer' else 'agent' end,
          'payment.proof_attached', 'order', p_order_id::text, jsonb_build_object('proof_id', v_id));

  return v_id;
end;
$$;

-- Buyer or agent adds a photo to an open dispute, up to three (FR-15).
create or replace function public.add_dispute_photo(p_order_id uuid, p_path text, p_bytes integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_o public.orders%rowtype;
  v_dispute public.disputes%rowtype;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  select * into v_o from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found';
  end if;
  if not (v_actor = v_o.buyer_id or (v_o.agent_id is not null and v_actor = v_o.agent_id)) then
    raise exception 'Not your order' using errcode = '42501';
  end if;
  select * into v_dispute from public.disputes d where d.order_id = p_order_id and d.status = 'open' for update;
  if not found then
    raise exception 'No open dispute for this order';
  end if;
  if cardinality(v_dispute.photo_paths) >= 3 then
    raise exception 'A dispute can have at most three photos';
  end if;
  if p_path is null or p_path not like ('disputes/' || p_order_id::text || '/%') then
    raise exception 'Photo must be stored in this order''s dispute folder';
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 307200 then
    raise exception 'Photo must be between 1 byte and 300 KB (FR-08)';
  end if;

  update public.disputes set photo_paths = photo_paths || p_path where id = v_dispute.id;
end;
$$;

-- Transition an order. Adds: Declined and Cancelled need a reason; Accepted moves on to
-- AwaitingPayment in the same call. Everything else as in 20261119000004.
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
  v_state public.order_state := p_to;
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

  if p_to in ('Declined', 'Cancelled') and (p_note is null or length(trim(p_note)) = 0) then
    raise exception 'A reason is required to % this order', lower(p_to::text);
  end if;

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

  if p_to = 'Confirmed' then
    update public.orders
       set state = 'Confirmed',
           updated_at = now(),
           confirmed_at = now(),
           confirmation_type = v_conf_type,
           commission = v_comm,
           minimum_applied = v_comm_min
     where id = v_order.id;
  elsif p_to = 'Declined' then
    update public.orders
       set state = 'Declined', updated_at = now(), decline_reason = trim(p_note)
     where id = v_order.id;
  elsif p_to = 'Cancelled' then
    update public.orders
       set state = 'Cancelled', updated_at = now(), cancel_reason = trim(p_note)
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

  -- Accepted moves on to AwaitingPayment in the same call (system step, recorded as system).
  if p_to = 'Accepted' then
    update public.orders set state = 'AwaitingPayment', updated_at = now() where id = v_order.id;
    insert into public.order_events (order_id, from_state, to_state, actor_user_id, actor_role, note)
    values (v_order.id, 'Accepted', 'AwaitingPayment', null, 'system', 'Automatic after accept');
    insert into public.audit_log (actor_user_id, actor_role, action, entity, entity_id, before, after)
    values (null, 'system', 'order.transition', 'order', v_order.id::text,
            jsonb_build_object('state', 'Accepted'),
            jsonb_build_object('state', 'AwaitingPayment'));
    v_state := 'AwaitingPayment';
  end if;

  v_result := jsonb_build_object('order_id', v_order.id, 'code', v_order.code, 'state', v_state);

  if p_client_id is not null then
    insert into public.client_actions (client_id, actor_user_id, action, entity_id, result)
    values (p_client_id, v_actor, 'order.transition', v_order.id::text, v_result);
  end if;

  return v_result;
end;
$$;

-- Admin reverses a payment (FR-12): marks the payment reversed with a reason and returns the
-- order to AwaitingPayment. Not possible once the goods have shipped.
create or replace function public.admin_reverse_payment(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_payment_id uuid;
  v_result jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Only admin can reverse a payment' using errcode = '42501';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to reverse a payment';
  end if;

  select p.id into v_payment_id from public.payments p
   where p.order_id = p_order_id and p.reversed_at is null
   for update;
  if not found then
    raise exception 'No active payment to reverse';
  end if;

  update public.payments
     set reversed_at = now(), reversed_by = v_actor, reversal_reason = trim(p_reason)
   where id = v_payment_id;

  v_result := public.transition_order(p_order_id, 'AwaitingPayment', null, null,
                                      'Pembayaran dibatalkan: ' || trim(p_reason));

  return v_result || jsonb_build_object('payment_id', v_payment_id);
end;
$$;

-- Function access.
revoke execute on function public.queue_order_notifications() from public, anon, authenticated, service_role;

revoke execute on function public.get_payment_instructions(uuid) from public, anon;
revoke execute on function public.attach_payment_proof(uuid, text, integer) from public, anon;
revoke execute on function public.add_dispute_photo(uuid, text, integer) from public, anon;
revoke execute on function public.admin_reverse_payment(uuid, text) from public, anon;
revoke execute on function public.transition_order(uuid, public.order_state, uuid, text, text) from public, anon;

grant execute on function public.get_payment_instructions(uuid) to authenticated, service_role;
grant execute on function public.attach_payment_proof(uuid, text, integer) to authenticated, service_role;
grant execute on function public.add_dispute_photo(uuid, text, integer) to authenticated, service_role;
grant execute on function public.admin_reverse_payment(uuid, text) to authenticated, service_role;
grant execute on function public.transition_order(uuid, public.order_state, uuid, text, text) to authenticated, service_role;
