-- Reference data: towns, categories, decided configuration, transition rules.
-- Source: docs/business-requirements.md sections 5 and 10; docs/product-spec.md section 3.

insert into public.towns (code, name, active) values
  ('J', 'Jayapura', true),
  ('W', 'Wamena', true);

insert into public.town_sequences (town_id, last_seq)
select id, 0 from public.towns;

insert into public.categories (id, name, restricted, rate_bp) values
  ('staples', 'Bahan pokok', false, 150),
  ('school_office', 'Perlengkapan sekolah dan kantor', false, 300),
  ('household', 'Kebutuhan rumah tangga', false, 300),
  ('electronics_tools', 'Elektronik dan alat', false, 200),
  ('restricted', 'Barang terlarang', true, null);

-- Confirmed by founder (BR-02). Undecided values are deliberately NOT inserted:
-- auto_confirm_days (D-006), overdue_block_days (D-007), agent_fee_per_order (D-008).
insert into public.config (key, value, reason) values
  ('minimum_commission', '25000'::jsonb, 'BR-02: Rp25,000 minimum per order, applied once per order');

insert into public.order_transitions (from_state, to_state, allowed_actors) values
  ('Placed', 'Accepted', array['distributor']),
  ('Placed', 'Declined', array['distributor']),
  ('Accepted', 'AwaitingPayment', array['system']),
  ('AwaitingPayment', 'Paid', array['distributor']),
  ('AwaitingPayment', 'Cancelled', array['admin', 'system']),
  ('Paid', 'Shipped', array['distributor']),
  ('Shipped', 'Confirmed', array['buyer', 'system']),
  ('Shipped', 'Disputed', array['buyer', 'agent']),
  ('Disputed', 'Confirmed', array['admin']),
  ('Disputed', 'Cancelled', array['admin']);
