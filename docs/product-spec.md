# Product specification: MitraLink MVP

Status: draft for review. Read the [business requirements](business-requirements.md) first. Rule IDs (BR-xx) refer to that document.

Two front ends share one backend:

- **Mobile app** (buyers, agents, distributors): ordering, status, confirmations, agent work. Designed for low-cost Android and offline use.
- **Web dashboard** (distributors and admins): catalogue management, order and invoice handling, approvals, reports. Online-first.

## 1. Personas

| Persona | Device | Connection | Key needs |
|---|---|---|---|
| **Ibu Ani**, kios owner in Wamena | Low-cost Android, 2 GB RAM | Intermittent mobile data, long offline stretches | Order the same goods each week, see what has shipped, confirm receipt |
| **Pak Yohanes**, agent in Jayapura | Android phone | Mobile data, some offline time | Register buyers, place orders for them, know what he will earn |
| **Bu Marta**, distributor (CV Papua Sejahtera) | Android or laptop | Office connection, sometimes slow | See new orders quickly, confirm payments, ship, pay commission |
| **Ops admin** (the founder) | Laptop | Office connection | Approve distributors, match payments, invoice, pay agents, track targets |

Personas are illustrative. Replace them with real users after the test.

## 2. Principles

1. **Order first.** The core task is placing and confirming an order. Every screen serves that task.
2. **Offline by default for buyers and agents.** Show last-synced data, queue actions, and show clearly what is pending.
3. **No money mistakes.** Commission and totals are calculated on the server. Status changes that move money are confirmed, logged and reversible only by a new entry.
4. **Simple language.** Bahasa Indonesia, short sentences, labels next to icons, large touch targets (at least 44 px).
5. **Small payloads.** Compressed images, paged lists, no background downloads on mobile data.

## 3. Order state machine

```
Placed ──accept──▶ Accepted ──request payment──▶ AwaitingPayment ──PAID──▶ Paid ──SHIP──▶ Shipped ──RECEIVED──▶ Confirmed
  │                    │                              │                                       │
  └──decline──▶ Declined  └──cancel (unpaid after window)──▶ Cancelled                    dispute ──▶ Disputed ──resolved──▶ Confirmed or Cancelled
                                                                                              │
                                                                       auto-confirm after N days (BR-06) ──▶ Confirmed
```

| State | Set by | Allowed next |
|---|---|---|
| Placed | Buyer or agent | Accepted, Declined |
| Accepted | Distributor | AwaitingPayment |
| AwaitingPayment | System (on accept) | Paid, Cancelled |
| Paid | Distributor (test) or gateway (Phase 2) | Shipped |
| Shipped | Distributor | Confirmed (buyer), Disputed |
| Confirmed | Buyer, or auto-confirm | (terminal; invoiced via commission) |
| Declined | Distributor | (terminal) |
| Cancelled | Admin or system | (terminal) |
| Disputed | Buyer | Confirmed or Cancelled (admin decides) |

Every transition writes an event (who, when, device, previous state, new state). Commission is calculated when an order reaches Confirmed.

## 4. Functional requirements

Each requirement lists its priority (MVP or Phase 2), the business rules it implements, and acceptance criteria.

### 4.1 Accounts and access

**FR-01 Phone-based login (MVP).** Users sign in with their phone number and a one-time code sent by SMS or WhatsApp.
- Given a registered phone number, when the user requests a code, then a code arrives within 60 seconds and is valid for 5 minutes.
- Given a wrong code three times, then the request is blocked for 15 minutes.

**FR-02 Buyer registration (MVP).** A buyer, or an agent on their behalf, enters name, business name, business type, town and phone. The buyer accepts the terms (version recorded).
- Given a complete form, when submitted, then the buyer is active immediately and linked to the agent who registered them.
- Given a duplicate phone number, then the form shows "Nomor ini sudah terdaftar" and does not create a second account.

**FR-03 Distributor registration and approval (MVP).** A distributor uploads business registration and tax documents and bank account details. Admin approves or rejects.
- Given an unapproved distributor, then it cannot publish a catalogue or receive orders.
- Given an approval, then the distributor's commission terms (BR-03) are recorded with the approval date.

**FR-04 Agent registration (MVP).** Admin creates agent accounts. Agents see only their own buyers and orders.

**FR-05 Roles and permissions (MVP).** Permissions follow the matrix in section 6.

### 4.2 Catalogue and browsing

**FR-06 Browse catalogue (MVP).** Buyers see products from approved distributors in their town, filtered by category, with price, unit and availability.
- Given no connection, then the last synced catalogue is shown with the time it was synced.
- Given a product marked unavailable, then it is shown greyed out and cannot be added to an order.

**FR-07 Restricted goods (MVP).** Distributors cannot publish restricted goods (BR-08). Admin can review and remove listings.

**FR-08 Distributor catalogue management (MVP, web).** Distributors add, edit and hide products with name, category, unit, price, availability and an optional photo (compressed to under 300 KB).

### 4.3 Ordering

**FR-09 Place an order (MVP).** A buyer or agent builds a basket from one distributor and submits it.
- Given items from two distributors, then two orders are created, one per distributor.
- Given the app is offline, when the user submits, then the order is saved locally with a client-generated ID, marked "Menunggu sinkron", and synced later.
- Given the same order is sent twice (retry), then only one order exists (NFR-03).
- The order code follows the format `PDC-<town code>-<number>` and is shown to the buyer.

**FR-10 Accept or decline (MVP).** The distributor sees new orders and accepts or declines each one.
- Given a decline with a reason, then the buyer and agent are notified.
- Given an accept, then the state becomes AwaitingPayment and the buyer sees the bank account and the order code to quote.

**FR-11 Payment reference (MVP).** The buyer sees the amount to transfer and the order code. The buyer can attach a transfer proof photo, which is kept for records but is not proof of payment on its own (BR-05).

**FR-12 Mark paid (MVP).** The distributor marks an order PAID after checking its bank statement.
- Given an order not yet PAID, then the distributor cannot mark it SHIP.
- Given PAID is set in error, then an admin can reverse it with a reason; the reversal is logged (BR-13).

**FR-13 Ship (MVP).** The distributor marks SHIP with a date. Only allowed after PAID (BR-05).

**FR-14 Confirm receipt (MVP).** The buyer confirms RECEIVED. Only the buyer can do this (BR-12).
- Given no action within the auto-confirm period and no dispute, then the order is Confirmed automatically (BR-06). The buyer gets a reminder before this happens.

**FR-15 Dispute (MVP).** The buyer raises a dispute with a reason and up to three photos. The order is frozen and the admin is notified.

**FR-16 Cancel (MVP).** An order is cancelled automatically if not paid within the agreed window, or manually by admin with a reason.

### 4.4 Commission and invoices

**FR-17 Commission calculation (MVP).** On Confirmed, the server calculates commission per order: higher of (order value × category rate) and Rp25,000 (BR-02, BR-03, BR-04). Each order line stores the rate and the calculation.
- Example: basket Rp1,000,000, staples 1.5%. Commission is Rp25,000 (the minimum), not Rp15,000.
- Example: basket Rp2,000,000, electronics 2%. Commission is Rp40,000.

**FR-18 Weekly commission invoice (MVP).** Each week the system issues one invoice per distributor listing its Confirmed orders in that week, with totals.
- Given a distributor with no confirmed orders, then no invoice is issued.
- The invoice includes the bank account for payment and a unique invoice number.

**FR-19 Invoice payment (MVP).** Admin marks an invoice paid with the bank statement reference.
- Given an invoice unpaid after the due date, then the distributor is flagged and, after the block period, new orders to that distributor are blocked (BR-10).

**FR-20 Tax fields (MVP).** The system stores tax-relevant fields (distributor tax number, invoice number, amounts before and after tax if applicable) without calculating tax (BR-16).

### 4.5 Agent

**FR-21 Agent dashboard (MVP).** The agent sees their buyers, orders in progress, Confirmed orders this month, and expected earnings.

**FR-22 Agent payout (MVP).** At month end the system lists Confirmed orders whose commission is paid, and calculates the agent fee (current proposal: Rp5,000 per order, BR-11). Admin pays and marks the payout.
- Given an order whose commission is not yet paid, then it is excluded from the payout.

**FR-23 Agent places orders (MVP).** The agent can create an order on behalf of a buyer. The order is recorded with both buyer and agent names.

### 4.6 Notifications

**FR-24 Status notices (MVP).** The system notifies buyer, agent and distributor on: new order, accepted or declined, payment needed, paid, shipped, receipt needed, confirmed, dispute, invoice due.
- Channel: in-app and SMS for MVP. WhatsApp templates are added once approved by Meta (Phase 2 or late MVP).
- Notifications are sent in Bahasa Indonesia.

**FR-25 Reminders (MVP).** Reminders go out before auto-confirm, and for unpaid orders at the payment window.

### 4.7 Admin and reporting

**FR-26 Admin console (MVP, web).** Admin manages users, approvals, orders, disputes, invoices, payouts and configuration (commission rates, minimum, block period, auto-confirm period).
- Every configuration change is logged with the old and new value.

**FR-27 Reports (MVP, web).** Weekly and monthly reports for the KPIs in the business requirements: distributors signed, buyers ordering, orders per week, on-time confirmation, invoices paid, dispute rate.

**FR-28 Audit log (MVP).** Every status change, payment mark, invoice payment and configuration change is viewable by admin, with who, when and device.

### 4.8 Offline and sync

**FR-29 Offline queue (MVP).** Buyer and agent actions taken offline (place order, confirm receipt, raise dispute) are queued and sent in order when online. Each action has a client ID.
- Given a queued action that conflicts with a later server state (for example, the order was cancelled), then the user sees the conflict and the action is not applied silently.

**FR-30 Sync status (MVP).** The app shows a clear indicator: all synced, or N items waiting, or last synced time.

**FR-31 Data cache (MVP).** The catalogue, the user's own orders and their last 30 days of history are cached on the device. Old data is removed to stay within device storage limits.

## 5. Screens

### 5.1 Mobile app (Android first, React Native or Flutter per decision)

**Buyer and agent**

| Screen | Purpose | Key elements |
|---|---|---|
| Sign in | Phone login with code | Phone field, send code, code field |
| Home | Start an order, see status | Big button "Pesan barang", list of open orders, sync indicator |
| Catalogue | Browse by category | Category tabs, product cards (name, price, unit, availability), search |
| Basket | Review and place order | Items with quantity, total, distributor name, "Kirim pesanan" |
| Order detail | Track status | Status steps, payment instruction and order code, actions for the current state |
| Pay instruction | Show transfer details | Bank name, account number with copy button, amount, order code to quote |
| Confirm receipt | Buyer confirms goods | Confirm button, dispute link |
| Dispute | Report a problem | Reason list, free text, photo upload |
| Orders list | History | Filter by status, search by order code |
| Profile | Account | Business details, language, sign out |
| Agent: My buyers | Recruited buyers | Name, town, orders this month |
| Agent: Earnings | Expected payout | Confirmed orders this month, amount, payout status |
| Agent: New buyer | Register a buyer | Same form as FR-02 |

**Distributor (mobile, simplified)**

| Screen | Purpose |
|---|---|
| Incoming orders | Accept or decline, with order detail |
| Awaiting payment | Mark PAID after checking bank |
| Ship | Mark SHIP with date |
| Invoices | View weekly invoice and status |

### 5.2 Web dashboard (distributor and admin)

**Distributor**

| Screen | Purpose |
|---|---|
| Catalogue | Add and edit products, availability, prices |
| Orders | List and detail, accept or decline, PAID, SHIP |
| Invoices | Weekly commission invoices, payment status |
| Profile and documents | Business details, bank account, terms |

**Admin**

| Screen | Purpose |
|---|---|
| Overview | KPIs against targets, alerts (overdue invoices, open disputes) |
| Users | Buyers, distributors, agents; approvals; suspension |
| Orders | All orders with filters; cancel; reverse PAID with reason |
| Disputes | Review, resolve, record outcome |
| Invoices | Generate, mark paid with bank reference, overdue list |
| Payouts | Agent payouts for the month, mark paid |
| Configuration | Rates, minimum, block period, auto-confirm period (logged) |
| Audit log | Searchable history |

## 6. Permissions matrix

| Action | Buyer | Agent | Distributor | Admin |
|---|---|---|---|---|
| Register buyer | Self | Yes (own buyers) | No | Yes |
| Place order | Yes | Yes (for own buyers) | No | Yes |
| Accept or decline | No | No | Yes (own orders) | Yes |
| Mark PAID | No | No | Yes (own orders) | Yes, with reason |
| Mark SHIP | No | No | Yes (own orders) | Yes, with reason |
| Confirm RECEIVED | Yes (own orders) | No | No | Yes, with reason |
| Raise dispute | Yes | Yes (on behalf) | No | No |
| Resolve dispute | No | No | No | Yes |
| Mark invoice paid | No | No | No | Yes |
| Mark payout paid | No | No | No | Yes |
| Change configuration | No | No | No | Yes |
| View audit log | No | No | Own orders | Yes |

## 7. Data model (MVP)

Money is stored as integer rupiah (BR-15).

| Entity | Key fields |
|---|---|
| User | id, phone, name, role, status, language, terms_version, created_at |
| Buyer | user_id, business_name, business_type, town_id, agent_id |
| Distributor | user_id, business_name, town_id, tax_number, bank_name, bank_account, approved_at, commission_terms_version, status |
| Agent | user_id, town_id, payout_fee_per_order, status |
| Town | id, name, code (for order codes) |
| Category | id, name, commission_rate_bp (basis points, e.g. 150 for 1.5%) |
| Product | id, distributor_id, category_id, name, unit, price, available, photo_url, updated_at |
| Order | id, code, client_id, buyer_id, agent_id (nullable), distributor_id, state, subtotal, created_at, updated_at |
| OrderItem | id, order_id, product_id, name_snapshot, unit_price, quantity, line_total |
| OrderEvent | id, order_id, from_state, to_state, actor_user_id, device, created_at, note |
| Payment | id, order_id, method (bank_transfer or gateway later), reference, amount, marked_by, marked_at, reversed_at, reversal_reason |
| Shipment | id, order_id, shipped_at, marked_by |
| Confirmation | id, order_id, type (received or auto), at |
| Dispute | id, order_id, reason, description, status, resolution, resolved_by, resolved_at |
| CommissionLine | id, order_id, category_id, rate_bp, basis_amount, commission_amount, minimum_applied |
| Invoice | id, number, distributor_id, period_start, period_end, total_commission, due_date, status, paid_at, bank_reference |
| AgentPayout | id, agent_id, period, order_count, amount, status, paid_at, reference |
| Config | key, value, changed_by, changed_at, previous_value |
| AuditLog | id, actor_user_id, action, entity, entity_id, before, after, device, created_at |

## 8. Commission logic (reference for implementation)

```
commission = max( round(order_value × rate_bp / 10000), 25000 )
minimum_applied = (order_value × rate_bp / 10000) < 25000
```

- `rate_bp` is the category rate in basis points (1.5% = 150).
- Confirmed by founder: the Rp25,000 minimum applies once per order, not per line. For an order with mixed categories, compute each line's commission, sum them, then apply the minimum to the total:
  `commission = max( sum(line commissions), 25000 )`
- Each line's commission is `round(line_value × rate_bp / 10000)`.
- Rounding: round half up to whole rupiah.

## 9. Order code format

`PDC-<TOWN>-<NNNN>`, where `<TOWN>` is the town code (for example `W` for Wamena, `J` for Jayapura) and `NNNN` is a sequence number per town, zero-padded. Codes are unique and never reused.

## 10. Offline and sync design

- Local database on device (SQLite) holds cached catalogue, own orders and an outbox of queued actions.
- Each queued action has a client ID, type, payload and timestamp. The server accepts each action once (idempotent).
- Server is the source of truth for state. Conflicts are reported to the user, never silently merged.
- Sync runs when the app opens and when connection returns. Retries back off gradually.
- Backend sync layer: PowerSync (default) or a custom outbox endpoint if PowerSync is rejected.

## 11. Security and privacy

- Row-level security in the database: each user reads and writes only their own records (NFR-06).
- Session tokens are stored in secure device storage.
- Upload only through signed URLs; scan or limit file types and sizes.
- No payment card data is stored. Bank account numbers are stored as entered and shown only to the buyer who needs them.
- Personal data retention and deletion follow BR-14. Retention periods to be set with the legal adviser.
- Audit log is append-only (BR-13).

## 12. Localisation and content

- All text is in Bahasa Indonesia. Strings are kept in one file so they can be reviewed by a native speaker.
- Currency format: `Rp1.000.000` (dot as thousands separator).
- Dates: `2 Des 2026` in short form, with 24-hour time.

## 13. Analytics events (MVP)

Track counts only, without personal data:

- `order_placed`, `order_accepted`, `order_declined`, `order_paid`, `order_shipped`, `order_confirmed`, `order_cancelled`, `dispute_raised`
- `buyer_registered`, `distributor_approved`
- `sync_failed` (with error category, not message content)
- `offline_queue_size` (sampled)

These feed the KPIs in the business requirements.

## 14. Acceptance test scenarios (end to end)

1. **Happy path:** buyer places order, distributor accepts, buyer pays, distributor marks PAID, ships, buyer confirms. Commission is calculated, invoiced and paid.
2. **Offline order:** buyer places order with no signal. Order appears as pending. Connection returns. Order is created once on the server.
3. **Duplicate retry:** the same queued order is sent twice. One order exists.
4. **Ship before pay:** distributor tries to mark SHIP before PAID. Action is blocked.
5. **Decline:** distributor declines. Buyer sees the reason. No commission.
6. **Dispute:** buyer raises dispute after shipment. Order is frozen. Admin resolves as Confirmed. Commission is calculated once.
7. **Auto-confirm:** buyer does not respond. Order confirms after the period. Reminder was sent first.
8. **Overdue invoice:** distributor does not pay within the due date. After the block period, new orders are blocked.
9. **Minimum commission:** Rp1,000,000 staples order produces Rp25,000 commission.
10. **Agent payout:** only orders whose commission is paid appear in the payout.
11. **Role access:** an agent cannot see another agent's buyers. A buyer cannot mark PAID.
12. **Low-end device:** the app launches, browses and places an order on a 2 GB RAM Android phone on a slow connection within the agreed time.

## 15. Release plan

| Release | Contents | Gate to next release |
|---|---|---|
| R0: test (now) | Spreadsheet, WhatsApp, bank statements | Week 4 decision: build |
| R1: MVP pilot | Buyer and agent mobile app, distributor web dashboard, admin console, commission and invoices, offline ordering, SMS notices | 2 distributors live, 30 buyers, scenarios 1 to 12 pass |
| R2: scale | WhatsApp notices, reports, more towns, paid listings (if approved) | Stable pilot for 4 weeks, KPIs on target |
| R3: payments | Gateway with split payouts (after BR-09 review) | Legal approval, gateway contract, reconciliation tested |

## 16. Open questions

See section 10 of the business requirements. Specific to the product:

1. ~~Commission minimum per order versus per line~~ Resolved: per order (section 8).
2. Photo requirement for products: optional or required.
3. Whether buyers can order from more than one distributor in one basket (current spec: one order per distributor).
4. Language support beyond Bahasa Indonesia (Papuan languages) for later.
