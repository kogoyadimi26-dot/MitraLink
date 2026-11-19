# Business requirements: MitraLink

Status: draft for review. Source: [business plan](business-plan.md), [business model](business-model.md), [test plan](test-plan.md), [terms](terms-and-conditions.md).

## 1. Purpose

MitraLink lets kios, warung, schools and churches in Papua find and order from local distributors, while distributors ship and pay a commission to MitraLink on each confirmed order.

The app exists to replace the manual steps of the test (spreadsheet, WhatsApp, bank statement matching) with a system that is faster, less error-prone and auditable. It must work for buyers on slow or intermittent connections and on low-cost Android phones.

## 2. Objectives

| ID | Objective | Measure |
|---|---|---|
| OBJ-01 | Grow confirmed orders | Confirmed orders per month (MVP target: 40 to break even, 315 for Rp5M net profit under current terms) |
| OBJ-02 | Earn commission reliably | Share of commission invoices paid on time (target 100%) |
| OBJ-03 | Keep orders trustworthy | Share of orders confirmed on time (target 80%) |
| OBJ-04 | Keep operating cost low | Fixed monthly costs about Rp745,000 at launch |
| OBJ-05 | Serve buyers offline | Orders placed offline sync without loss |

## 3. Stakeholders

| Stakeholder | Interest |
|---|---|
| Founder / operator | Revenue, cost, fraud control, legal compliance |
| Buyer (kios, warung, school, church) | Find suppliers, order simply, know status, get goods |
| Distributor | Reach new buyers, get paid, avoid non-payment, manage stock and orders |
| Agent | Recruit buyers, take orders, get paid per confirmed order |
| Platform admin (ops) | Approve distributors, resolve disputes, reconcile payments |
| Regulators and tax (BI, DJP) | Lawful payment handling, tax on commission |

## 4. Scope

### 4.1 In scope: MVP (app phase, after the test)

- Buyer registration and login (phone number based), with agent-assisted registration.
- Distributor registration with business documents, approved by admin.
- Catalogue: distributor products by category, price, unit and availability, filtered by town.
- Ordering: buyer or agent places an order with a distributor; distributor accepts or declines.
- Payment tracking: bank transfer reference and distributor confirmation of PAID. Admin reconciliation.
- Fulfilment: distributor marks SHIP; buyer marks RECEIVED; disputes can be raised.
- Commission: calculated automatically per order; weekly invoice per distributor; payment tracking.
- Agent: buyer list, orders created, confirmed orders, earnings per month.
- Admin: approvals, disputes, invoices, payouts to agents, reports for the success targets.
- Notifications: in-app and SMS or WhatsApp notices for key status changes (WhatsApp templates require approval).
- Offline ordering for buyers and agents, with sync when online.
- Bahasa Indonesia as the default language.

### 4.2 Out of scope for MVP

- Payment gateway and split payouts (Phase 2, after a legal check, see BR-09).
- Automatic WhatsApp order intake through the WhatsApp Business API (Phase 2).
- Paid distributor listings or verified badges (later, price not set).
- Inventory management and stock sync with distributors' own systems.
- Delivery tracking by courier.
- Credit terms for buyers.
- Ratings and reviews (Phase 2, after enough confirmed orders).

## 5. Business rules

These rules are authoritative. Any feature that conflicts with them needs an explicit decision and an update here first.

| ID | Rule |
|---|---|
| BR-01 | Buyers never pay MitraLink for joining or ordering. |
| BR-02 | Commission per confirmed order is the higher of (order value × category rate) and Rp25,000. |
| BR-03 | Category rates for test: staples 1.5%, school and office supplies 3%, household goods 3%, electronics and tools 2%. Restricted goods cannot be listed. Rates are configurable by admin, never hard-coded. |
| BR-04 | Commission is calculated on the server and stored in whole rupiah. The app may display an estimate, never the final figure. |
| BR-05 | A distributor may ship only after a payment is marked PAID. In the test, PAID is set by the distributor after checking the bank statement. In Phase 2, PAID is set by the gateway. |
| BR-06 | An order is Confirmed only when the buyer marks RECEIVED, or after the auto-confirm period if no dispute is raised. The auto-confirm period is [N days, to be decided]. |
| BR-07 | Only Confirmed orders count toward targets, commission and agent pay. |
| BR-08 | Commission is invoiced weekly per distributor. Payment is due within [7] days. |
| BR-09 | During the test, MitraLink never receives or holds buyer money. Phase 2 gateway split payments need a legal and Bank Indonesia review before build. |
| BR-10 | If a distributor's invoice is overdue by more than [7] days, new orders to that distributor are blocked until paid. |
| BR-11 | Agents are paid per Confirmed order, monthly, only after the related commission is received. Current proposal: Rp5,000 per Confirmed order. |
| BR-12 | Agents and buyers cannot confirm their own orders as paid or shipped. Only the distributor (for PAID and SHIP) and the buyer (for RECEIVED) can. |
| BR-13 | Every status change is recorded with who, when and from which device. Records are never deleted, only corrected by a new entry. |
| BR-14 | Personal data is handled under Law No. 27 of 2022 (personal data protection). Users can request access, correction or deletion, subject to record-keeping rules. |
| BR-15 | Amounts are in IDR, whole rupiah, with no floating-point arithmetic. |
| BR-16 | Tax treatment (PPN, PPh on commission and agent pay) is confirmed by a tax adviser before the first real invoice. The app must store the tax fields it needs but not decide tax. |

## 6. Business process (MVP)

1. Distributor signs commission terms and is approved by admin.
2. Buyer is registered by themselves or an agent.
3. Buyer browses the distributor catalogue for their town.
4. Buyer or agent places an order. The distributor receives it.
5. Distributor accepts or declines. If accepted, it asks the buyer to pay.
6. Buyer transfers the basket value to the distributor, with the order code as reference.
7. Distributor confirms PAID after checking its bank statement.
8. Distributor ships and marks SHIP.
9. Buyer marks RECEIVED, or the auto-confirm period passes. Order becomes Confirmed.
10. System calculates commission. Weekly invoice is issued per distributor.
11. Distributor pays the invoice. Admin marks it paid.
12. At month end, agent payouts are calculated for Confirmed orders whose commission is paid. Admin pays agents and marks them paid.

## 7. Key performance indicators

| KPI | Definition | Target (test) |
|---|---|---|
| Distributors signed | Approved distributors with commission agreed in writing | 3 of 5 |
| Buyers ordering | Registered buyers with at least one order | 10 of 30 |
| Orders per week | Orders created in the week | 10 or more |
| On-time confirmation | Confirmed orders within the agreed window | 80% |
| Invoices paid | Commission invoices paid on time | 100% |
| Dispute rate | Disputed orders ÷ shipped orders | Monitor, no target yet |

## 8. Constraints and assumptions

- **Connectivity:** many buyers have no signal for long periods. Ordering and viewing must work offline. Sync must not lose data.
- **Devices:** low-cost Android phones, often with 2 to 3 GB RAM and limited storage. Mobile app must run well on them.
- **Data cost:** buyers pay for data. Payloads and images must be small.
- **Language and literacy:** Bahasa Indonesia; simple wording; icons with labels; large touch targets.
- **Team:** one founder plus agents. Development is limited, so the MVP must be small.
- **Payments:** bank transfer only in the test. Buyer trust depends on clear payment and receipt records.
- **Assumptions to validate:** average basket size, buyer order frequency, distributor acceptance of the minimum commission, willingness to use the app.

## 9. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-01 | Works offline for browsing catalogue (last synced data) and creating orders. |
| NFR-02 | No order is lost when the app is closed or the connection drops; orders are retried until synced. |
| NFR-03 | Duplicate submissions do not create duplicate orders (client-generated IDs). |
| NFR-04 | Every money calculation is reproducible from stored order data. |
| NFR-05 | Sensitive actions (PAID, SHIP, RECEIVED, invoice payment) are logged with user and time. |
| NFR-06 | Each user sees only their own data (buyer, agent, distributor, admin). |
| NFR-07 | Mobile app is usable on Android 8 and later and on 2 GB RAM devices. Target app size and load times are to be set after the first build. |
| NFR-08 | Fixed monthly running cost stays within the launch budget unless the business approves a change. |
| NFR-09 | Backups of the database are kept, and restore is tested before launch. |
| NFR-10 | All user-facing text is available in Bahasa Indonesia. |

## 10. Open decisions

1. Auto-confirm period for RECEIVED (BR-06).
2. Overdue invoice block period (BR-10).
3. Agent fee amount (BR-11).
4. Minimum commission: stay at Rp25,000 or move to Rp30,000 after the test (current decision: Rp25,000).
5. Stack choice: React Native (Expo) or Flutter for mobile; Next.js for the web dashboard; Supabase and PowerSync as the backend and sync layer. Default in the product spec: React Native and Next.js.
6. Legal model for Phase 2 payments (BR-09).
7. Tax treatment (BR-16).
8. Which towns are in scope at launch beyond Wamena and Jayapura.
