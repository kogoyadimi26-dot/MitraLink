-- Phase 5: offline ordering and sync. Source: docs/product-spec.md sections 4.8 and 10
-- (FR-29 to FR-31, NFR-01 to NFR-03).
--
-- Each action queued on a phone is sent once, with a client id, to sync_action. It is applied
-- through the normal functions (so the same rules apply), and the result is returned and logged.
-- A conflict is never applied silently: it comes back as status 'conflict' with the reason, and the
-- app shows it to the user (FR-29). Replays with the same client id return the first result (NFR-03).
--
-- PowerSync reads changes through a publication. The sync rules that decide what each user gets are
-- in powersync/sync-rules.yaml.

-- Log of queued actions and their outcome. Written only by sync_action.
create table public.sync_log (
  id bigint generated always as identity primary key,
  client_id uuid not null unique,
  actor_user_id uuid not null,
  action text not null,
  status text not null check (status in ('applied', 'duplicate', 'conflict', 'rejected')),
  reason text,
  result jsonb,
  received_at timestamptz not null default now()
);

alter table public.sync_log enable row level security;
create policy sync_log_read on public.sync_log for select to authenticated
  using (actor_user_id = auth.uid() or public.is_admin());
revoke all on public.sync_log from anon;
revoke insert, update, delete on public.sync_log from authenticated;

-- Apply one queued action. Actions: place_order, transition, dispute_photo, payment_proof.
create or replace function public.sync_action(p_client_id uuid, p_action text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_prev public.sync_log%rowtype;
  v_result jsonb;
  v_status text;
  v_reason text;
begin
  if v_actor is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_client_id is null or p_action is null or p_payload is null then
    raise exception 'client_id, action and payload are required';
  end if;

  -- Same action sent again: return what happened the first time (NFR-03).
  select * into v_prev from public.sync_log where client_id = p_client_id;
  if found then
    return jsonb_build_object('status', 'duplicate', 'reason', v_prev.reason,
                              'original_status', v_prev.status, 'result', v_prev.result);
  end if;

  begin
    case p_action
      when 'place_order' then
        v_result := public.place_order(
          p_client_id,
          (p_payload ->> 'buyer_id')::uuid,
          (p_payload ->> 'distributor_id')::uuid,
          p_payload -> 'items');
      when 'transition' then
        v_result := public.transition_order(
          (p_payload ->> 'order_id')::uuid,
          (p_payload ->> 'to')::public.order_state,
          p_client_id,
          p_payload ->> 'reference',
          p_payload ->> 'note');
      when 'dispute_photo' then
        perform public.add_dispute_photo(
          (p_payload ->> 'order_id')::uuid,
          p_payload ->> 'path',
          (p_payload ->> 'bytes')::integer);
        v_result := jsonb_build_object('order_id', p_payload ->> 'order_id');
      when 'payment_proof' then
        v_result := jsonb_build_object('proof_id', public.attach_payment_proof(
          (p_payload ->> 'order_id')::uuid,
          p_payload ->> 'path',
          (p_payload ->> 'bytes')::integer));
      else
        raise exception 'Unknown action: %', p_action;
    end case;
    v_status := 'applied';
    v_reason := null;
  exception
    when sqlstate '42501' then
      -- Not allowed for this user (wrong role or not their order): rejected.
      v_status := 'rejected';
      v_reason := sqlerrm;
      v_result := null;
    when others then
      -- The server state no longer allows this (for example, the order was cancelled).
      -- Report it as a conflict. Nothing was applied.
      v_status := 'conflict';
      v_reason := sqlerrm;
      v_result := null;
  end;

  insert into public.sync_log (client_id, actor_user_id, action, status, reason, result)
  values (p_client_id, v_actor, p_action, v_status, v_reason, v_result);

  return jsonb_build_object('status', v_status, 'reason', v_reason, 'result', v_result);
end;
$$;

-- Publication for PowerSync: the tables it may replicate. Sync rules decide what each user receives.
-- Sensitive tables (distributor_private, audit_log, client_actions, sync_log, town_sequences) are left out.
create publication powersync for table
  public.towns,
  public.categories,
  public.config,
  public.profiles,
  public.buyers,
  public.agents,
  public.distributors,
  public.products,
  public.orders,
  public.order_items,
  public.order_events,
  public.payments,
  public.payment_proofs,
  public.shipments,
  public.confirmations,
  public.disputes,
  public.invoices,
  public.invoice_orders,
  public.notifications;

-- Function access.
revoke execute on function public.sync_action(uuid, text, jsonb) from public, anon;
grant execute on function public.sync_action(uuid, text, jsonb) to authenticated, service_role;
