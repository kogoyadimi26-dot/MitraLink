# Build plan: MitraLink end to end

Status: draft plan. Built from the [business requirements](business-requirements.md), the [product spec](product-spec.md), the [agent workflow](agent-workflow.md) and the [terms](terms-and-conditions.md). Requirement IDs (FR-xx, BR-xx, NFR-xx) refer to those documents.

Stack (confirmed): React Native with Expo (mobile), Next.js (web dashboard), Supabase with PowerSync (backend and offline sync).

## 1. Approach

- **Backend first.** Money, order state and permissions live on the server. Build and test them before any screen depends on them.
- **Thin vertical slices.** Each phase ships a working path through database, server, and the mobile and web screens it needs, rather than finishing one layer at a time.
- **Gates, not dates.** A phase ends when its exit gate passes: acceptance tests green, review checklist complete, founder sign-off. Calendar estimates are indicative and are re-estimated after Phase 0.
- **Release at the end of Phase 8.** Phases 0 to 8 build the pilot release (R1). Phases 9 and 10 run the pilot and the later releases (R2 and R3) from the product spec's release plan.
- **Test-phase fallback.** Until R1 is live, the spreadsheet and WhatsApp test continues. Nothing in the build replaces it before its exit gate passes.

## 2. Phase overview

| Phase | Name | Main output | Requirements covered | Release |
|---|---|---|---|---|
| 0 | Foundations | Repo, environments, CI, hello-world deploys | NFR-08, NFR-09 (setup) | R1 |
| 1 | Domain core | Schema, RLS, state machine, commission, audit, config | BR-01 to BR-16 (server side), FR-17, FR-28 (base) | R1 |
| 2 | Identity and onboarding | Phone login, buyer, distributor, agent accounts, roles | FR-01 to FR-05, NFR-06 | R1 |
| 3 | Catalogue | Products, browsing, restricted goods, photos | FR-06 to FR-08 | R1 |
| 4 | Ordering and fulfilment | Place, accept, pay, ship, confirm, dispute, cancel, notices | FR-09 (online), FR-10 to FR-16, FR-23, FR-24 | R1 |
| 5 | Offline and sync | Local database, outbox, sync status, conflict handling | FR-09 (offline), FR-29 to FR-31, NFR-01 to NFR-03 | R1 |
| 6 | Commission, invoices, payouts | Weekly invoices, invoice payment, blocking, agent payouts, agent dashboard | FR-17 to FR-22, FR-25 | R1 |
| 7 | Admin and reporting | Admin console, KPI reports, audit viewer, configuration | FR-26, FR-27, FR-28 | R1 |
| 8 | Hardening and pilot readiness | Security review, performance, legal, backups, monitoring | NFR-04 to NFR-10 | R1 |
| 9 | Pilot | Live with 2 distributors, 30 buyers, 4 weeks | KPIs in business requirements | R1 to R2 decision |
| 10 | Scale and payments | WhatsApp notices, more towns, reports, gateway (R3 only after legal review) | FR-24 (WhatsApp), BR-09 | R2, R3 |

## 3. Team and agent roles

The roles are the ones in [agent-workflow.md](agent-workflow.md) section 2.

| Role | Who | Works mainly in |
|---|---|---|
| Founder | You | Decisions, approvals, legal, operations |
| Spec agent | Claude Code session | `docs/`, requirement traceability |
| Backend agent | Claude Code session | `supabase/`, `packages/shared/` |
| Mobile agent | Claude Code session | `apps/mobile/` |
| Web agent | Claude Code session | `apps/web/` |
| QA agent | Claude Code session | `tests/`, test reports |
| Review agent | Claude Code session | Pull request review, no merges |

The founder approves each gate and merges each pull request. Agents never merge.

## 4. Repository layout (set up in Phase 0)

```
MitraLink/
├── apps/
│   ├── mobile/          Expo app (buyers, agents, distributors on mobile)
│   └── web/             Next.js app (distributor dashboard, admin console)
├── packages/
│   └── shared/          Money, commission, state machine, order code, strings, types
├── supabase/
│   ├── migrations/      Schema, RLS policies, functions, cron jobs
│   ├── functions/       Edge functions (transitions, invoices, payouts, notices)
│   └── tests/           Database and RLS tests
├── powersync/           Sync rules and configuration
├── tests/               End-to-end scenarios (product spec section 14)
├── docs/                Specs, plans, workflow
└── .claude/skills/      Agent skills
```

Rule: business logic lives in `packages/shared/` and is called from the server. The apps import it for display only; they never decide commission or state.

## 5. Phases in detail

### Phase 0: Foundations

**Objective:** every later phase can deploy and test from day one.

**Tasks**
- Create the layout in section 4. Configure TypeScript, linting and formatting.
- Create three Supabase projects: dev, staging, production. Enable point-in-time backups on production (NFR-09).
- Create a PowerSync project linked to the Supabase dev project. Check the free-tier limits before enabling it (cost check).
- Set up Vercel for the web app (Pro plan, since the app is commercial).
- Set up Expo with EAS builds for Android internal testing.
- Register the Google Play developer account ($25).
- Set up CI: lint, type check, unit tests, database tests on every pull request.
- Create the Bahasa Indonesia string file with keys, starting empty.
- Create `.env.example` for each app; keep real secrets out of the repository.
- Set up error monitoring (free tier) for mobile and web.

**Deliverables:** repo skeleton, three environments, CI passing on an empty test suite, a "hello" page on staging web, an internal build of the app on a test phone.

**Decisions needed:** Supabase region (closest available to Indonesia), Play account owner and verification documents.

**Exit gate**
- [ ] CI green on the feature branch, and on the default branch once it exists
- [ ] Staging web page reachable; internal Android build installs on a low-end test phone
- [ ] Production backups enabled
- [ ] Cost check recorded: monthly subscriptions match the budget (business model)

### Phase 1: Domain core (backend)

**Objective:** the rules of the business are enforced in code and database before any screen exists.

**Tasks**
- Schema for the entities in product spec section 7: User, Buyer, Distributor, Agent, Town, Category, Product, Order, OrderItem, OrderEvent, Payment, Shipment, Confirmation, Dispute, CommissionLine, Invoice, AgentPayout, Config, AuditLog.
- Money stored as integer rupiah (BR-15). Rates as basis points.
- `packages/shared`: money helpers (rounding half up), commission function (product spec section 8), order code generator (`PDC-<TOWN>-<NNNN>`), state machine table.
- Server functions for every order transition (product spec section 3). Reject any transition not in the table. Write an `OrderEvent` for each.
- Idempotency table for client IDs (NFR-03).
- Config table with the seeded test values from the business requirements (rates, Rp25,000 minimum). Auto-confirm and block periods are stored as **unset**. Code that needs them refuses to run until set (open decisions).
- Audit log: append-only, no update or delete policies (BR-13).
- Row-level security on every table, per the permissions matrix (product spec section 6).
- Commission lines stored per order, with the rate used, so each figure can be reproduced.

**Tests**
- Unit tests for money and commission, including the examples in FR-17 (Rp1,000,000 staples gives Rp25,000; Rp2,000,000 electronics at 2% gives Rp40,000), and property tests that the result is always an integer and never below the minimum.
- Database tests: every transition allowed or rejected as the table says; SHIP rejected before PAID; RECEIVED accepted only from the buyer.
- RLS tests: one test per role per table (buyer, agent, distributor, admin, anonymous).

**Acceptance scenarios covered:** 4 (ship before pay), 9 (minimum commission), 11 (role access).

**Decisions needed before exit:** none blocking. Auto-confirm and block periods stay unset and the code refuses to run without them.

**Exit gate**
- [ ] All database and unit tests pass
- [ ] Scenarios 4, 9 and 11 pass at the server level
- [ ] Review checklist complete (agent-workflow section 7)

### Phase 2: Identity and onboarding

**Objective:** every user can sign in and has the right role.

**Tasks**
- Phone login with one-time code (FR-01). Choose and integrate the SMS provider (decision needed).
- Buyer registration, by themselves or by an agent (FR-02). Store terms version accepted.
- Distributor registration with documents and bank details, and admin approval (FR-03). Unapproved distributors cannot publish or receive orders.
- Agent creation by admin (FR-04).
- Role and permission enforcement across the apps (FR-05).
- Mobile screens: sign in, buyer registration, profile.
- Web: admin approvals list; distributor registration form.

**Tests:** login rate limits (FR-01 criteria), duplicate phone handling (FR-02), distributor blocked until approved (FR-03), role tests for each screen.

**Acceptance scenarios covered:** 11 (role access).

**Decisions needed:** SMS provider and sender name; document types accepted for distributor approval.

**Exit gate**
- [ ] Login works on the low-end test phone, including a slow connection
- [ ] Scenario 11 passes end to end
- [ ] Review checklist complete

### Phase 3: Catalogue

**Objective:** buyers can see what distributors sell in their town.

**Tasks**
- Product CRUD for distributors on the web dashboard (FR-08): name, category, unit, price, availability, optional photo.
- Photo pipeline: compress on upload to under 300 KB, store in Supabase Storage through signed URLs.
- Restricted goods check on publish (FR-07, BR-08). Admin review queue.
- Mobile catalogue: category tabs, search, product cards, town filter (FR-06).
- Paging for long lists (NFR, product spec section 10).
- Unavailable products greyed out and not orderable (FR-06).

**Tests:** publish rejected for a restricted category; photo over 300 KB compressed; unavailable product cannot be added to a basket (server-side check, not only UI).

**Decisions needed:** the list of towns at launch (business requirements section 10, item 8); the restricted goods list in the terms (section 5.3).

**Exit gate**
- [ ] A distributor can publish 20 products and a buyer can find them in their town
- [ ] Photo and paging limits verified on a low-end device
- [ ] Review checklist complete

### Phase 4: Ordering and fulfilment

**Objective:** the full order path works online, from placing to confirmed.

**Tasks**
- Basket and order placement, one order per distributor (FR-09, online only at this phase). Order code shown to the buyer.
- Distributor accept or decline with reason (FR-10).
- Payment reference screen with bank details and order code; optional transfer proof photo (FR-11).
- Mark PAID (FR-12), with admin reversal path for error.
- Mark SHIP with date (FR-13).
- Confirm RECEIVED (FR-14) and raise dispute with up to three photos (FR-15).
- Cancel for unpaid orders (FR-16), manual by admin or automatic at the payment window (once its period is set).
- Agent places orders for buyers (FR-23).
- Status notices by SMS for each change (FR-24, Bahasa Indonesia).
- Web: distributor orders list and detail, accept, PAID, SHIP.
- Mobile: basket, order detail with state steps, pay instruction, confirm receipt, dispute, orders list.

**Tests:** scenarios 1 (happy path, end to end), 5 (decline), 6 (dispute), each state transition on the mobile and web screens.

**Acceptance scenarios covered:** 1, 4, 5, 6.

**Decisions needed:** SMS templates text (Bahasa Indonesia, reviewed by a native speaker).

**Exit gate**
- [ ] Scenarios 1, 4, 5 and 6 pass end to end on staging
- [ ] Every transition writes an `OrderEvent`
- [ ] Review checklist complete

### Phase 5: Offline and sync

**Objective:** buyers and agents can order with no signal, and nothing is lost.

**Tasks**
- PowerSync setup: sync rules for catalogue (last synced), the user's own orders and 30 days of history (FR-31).
- Local outbox: queued actions with client IDs (FR-29). Place order, confirm receipt, raise dispute.
- Sync status indicator: all synced, N waiting, last synced time (FR-30).
- Conflict handling: if the server state changed (for example, the order was cancelled), show the conflict; never apply silently (FR-29).
- Server idempotency on client IDs (NFR-03).
- Storage limits: remove old cache to stay within device storage.
- Payload checks for each sync endpoint (NFR-01).

**Tests**
- Place an order with the network off; restore; order exists once (scenarios 2 and 3).
- Repeat a queued action twice; one order (scenario 3).
- Conflict: cancel on server while the buyer's confirm is queued; the buyer sees the conflict.
- Run the full path on a low-end device with a throttled connection (scenario 12, partial).

**Acceptance scenarios covered:** 2, 3, 12.

**Decisions needed:** PowerSync tier for pilot volumes (check the free tier limits recorded in Phase 0).

**Exit gate**
- [ ] Scenarios 2 and 3 pass automatically in CI using a network simulator
- [ ] Manual test on a 2 GB RAM Android phone: order offline, reconnect, confirm
- [ ] Cost check: PowerSync usage within the planned tier

### Phase 6: Commission, invoices and payouts

**Objective:** MitraLink earns and records its commission, and pays agents correctly.

**Tasks**
- On Confirmed, calculate commission lines and the order commission (FR-17, product spec section 8). Store with the rate used.
- Weekly invoice job per distributor, listing its Confirmed orders in the week (FR-18). Scheduled function; no invoice when there are no orders.
- Invoice payment marking by admin with bank reference (FR-19).
- Overdue detection and new-order block (FR-19, BR-10). **Requires the block period.** The code refuses to block until it is set.
- Tax fields stored, no tax calculation (FR-20, BR-16). **Requires the tax adviser's review before the first real invoice.**
- Agent payouts at month end for Confirmed orders whose commission is paid (FR-22, BR-11). **Requires the agent fee amount.**
- Agent dashboard: buyers, orders in progress, Confirmed this month, expected earnings (FR-21).
- Reminders before auto-confirm and before payment window expiry (FR-25). **Requires both periods.**
- Auto-confirm after the period with no dispute (FR-14, BR-06). **Requires the period.**

**Tests:** commission for a week of mixed orders reconciles to the invoice total; invoice not issued when no orders; overdue distributor blocked after the period; payout excludes unpaid commission (scenario 10); auto-confirm after the period and a reminder before it (scenario 7); overdue block (scenario 8); minimum commission (scenario 9).

**Acceptance scenarios covered:** 7, 8, 9, 10.

**Decisions needed (blocking this phase's exit):**
1. Auto-confirm period (BR-06)
2. Overdue block period (BR-10)
3. Agent fee (BR-11)
4. Tax adviser's sign-off on invoice fields (BR-16)

**Exit gate**
- [ ] Scenarios 7 to 10 pass with the decided values
- [ ] Commission and invoice totals match the spreadsheet for a test week (reconciliation check)
- [ ] Tax adviser has reviewed the invoice fields
- [ ] Review checklist complete

### Phase 7: Admin and reporting

**Objective:** the founder can run the business from the admin console and see the KPIs.

**Tasks**
- Admin overview: KPIs against targets, alerts for overdue invoices and open disputes (FR-27).
- User management: buyers, distributors, agents; approvals; suspension.
- Orders: all orders, filters, cancel, reverse PAID with a reason (FR-12, FR-26).
- Disputes: review, resolve, record outcome.
- Invoices: generate, mark paid, overdue list.
- Payouts: monthly agent list, mark paid.
- Configuration screen: rates, minimum, block period, auto-confirm period, each change logged with old and new value (FR-26).
- Audit log viewer, searchable (FR-28).
- KPI reports weekly and monthly (FR-27): distributors signed, buyers ordering, orders per week, on-time confirmation, invoices paid, dispute rate.

**Tests:** role access to each admin screen; configuration change logged; KPI figures match a manual count for the same data.

**Acceptance scenarios covered:** 11 (admin scope).

**Decisions needed:** none blocking.

**Exit gate**
- [ ] KPI report matches the spreadsheet for one week
- [ ] Every configuration change is in the audit log
- [ ] Review checklist complete

### Phase 8: Hardening and pilot readiness

**Objective:** the system is safe, legal, recoverable and fast enough for real users.

**Tasks**
- Security review: RLS audit across all tables, secrets scan, dependency audit, signed upload URLs tested.
- Personal data: retention periods set with the legal adviser; access, correction and deletion requests handled (BR-14).
- Terms and conditions: complete the placeholders, legal review, versioned acceptance at registration (FR-02).
- Backup and restore: restore a production backup into staging and verify (NFR-09).
- Performance: cold start and list load on a 2 GB Android device, with app size recorded (NFR-07).
- Accessibility: touch targets, labels, contrast; Bahasa Indonesia review by a native speaker (NFR-10).
- Monitoring: error reporting for mobile and web; alerts for failed sync and failed scheduled jobs.
- Runbook: how to approve a distributor, mark paid, resolve a dispute, reverse an error, restore data.
- Final test pass: all twelve acceptance scenarios on staging.
- Release candidate to internal Android testers, then to a closed Play testing track.

**Decisions needed:** legal sign-off on terms and personal data retention; production domain name.

**Exit gate**
- [ ] All acceptance scenarios 1 to 12 pass on staging
- [ ] Restore test completed and recorded
- [ ] Legal sign-off on terms and privacy notice
- [ ] Security review findings resolved or accepted by the founder in writing
- [ ] Review checklist complete for the release candidate

### Phase 9: Pilot (R1)

**Objective:** measure the business with the app, and decide whether to scale.

**Tasks**
- Onboard two distributors (Jayapura and Wamena), with signed commission terms.
- Onboard about 30 buyers through agents, and pay agents under the approved terms.
- Run the pilot for four weeks. Review KPIs weekly from the admin reports.
- Collect support issues. Fix blockers with patch releases.
- Compare pilot KPIs with the test targets (business requirements section 7).

**Exit gate (R2 decision)**
- [ ] KPI targets met for four weeks, or a documented decision to change the model
- [ ] No open blocker bugs
- [ ] Founder decision recorded in the business requirements

### Phase 10: Scale and payments (R2 and R3)

**R2 tasks (after pilot success)**
- WhatsApp notices through a business provider, after Meta template approval (FR-24).
- New towns, with their own order code prefixes.
- Extended reports.
- Paid listings, only if the price is approved and the business case is written.

**R3 tasks (only after legal review, BR-09)**
- Choose a licensed gateway; sign the contract; check its fees against the margin.
- Gateway payments and split payouts, with webhook-driven PAID (BR-05).
- Reconciliation between gateway reports and orders.
- Update the business rules, the terms and the privacy notice before release.

**Gate for R3:** legal approval recorded, gateway contract signed, reconciliation tested on staging for two weeks.

## 6. Decisions needed, by phase

| Decision | Needed by | Blocks |
|---|---|---|
| Supabase region | Phase 0 | Production setup |
| SMS provider and sender name | Phase 2 | Login |
| Distributor document types | Phase 2 | Approval flow |
| Towns at launch | Phase 3 | Catalogue and order codes |
| Restricted goods list | Phase 3 | Catalogue publish rules |
| SMS message wording | Phase 4 | Notices |
| PowerSync tier | Phase 5 | Pilot volume |
| Auto-confirm period | Phase 6 | Auto-confirm and reminders |
| Overdue block period | Phase 6 | Invoice blocking |
| Agent fee | Phase 6 | Payouts |
| Tax adviser sign-off | Phase 6 (before first real invoice) | Invoice fields |
| Legal sign-off on terms and personal data | Phase 8 | Pilot release |
| Production domain | Phase 8 | Release |
| Phase 2 payment model | Before Phase 10 | R3 |

Blocked work does not stop the rest. For example, Phase 6 can build the commission and invoice logic while the periods are unset, and enables blocking and auto-confirm only when the values are set.

## 7. Testing strategy

| Level | What | Where | When |
|---|---|---|---|
| Unit | Money, commission, state table, order code | `packages/shared` | Every commit |
| Database | Transitions, constraints, audit append-only | `supabase/tests` | Every pull request |
| RLS | Each role on each table | `supabase/tests` | Every pull request |
| API and function | Edge functions, idempotency, scheduled jobs | `supabase/tests` | Every pull request |
| Component | Mobile and web screens with mocked data | `apps/*` | Every pull request |
| Offline | Network off, reconnect, duplicate retry | `tests/` with a network simulator | Phase 5 onward, every release candidate |
| End to end | Acceptance scenarios 1 to 12 | `tests/` on staging | Each phase exit, every release candidate |
| Device | Low-end Android (2 GB RAM), throttled network | Manual checklist | Phase 5, Phase 8, each release |
| Security | RLS audit, secrets scan, dependency audit | CI plus review | Phase 8, then each release |
| Restore | Backup restored to staging | Manual, recorded | Phase 8, then quarterly |

Rule (agent workflow section 10): a failing test is reported with its output. It is never disabled to pass a gate.

## 8. Environments and releases

| Environment | Purpose | Data |
|---|---|---|
| Dev | Daily development | Fictitious fixtures |
| Staging | Acceptance tests, founder review, release candidates | Fictitious data, same configuration as production |
| Production | Pilot and live | Real data, backups enabled |

Mobile releases: internal testing track, then closed testing track with pilot users, then production after the pilot gate. Web releases: preview deployment per pull request, production on merge after approval.

## 9. Cost checkpoints

| Phase | Check |
|---|---|
| 0 | Supabase Pro, Vercel Pro, Play account, EAS plan match the budget |
| 5 | PowerSync usage projection within the tier |
| 6 | Notification and SMS costs per order against the margin (business model) |
| 8 | Monitoring tier and storage growth projected for 12 months |
| 9 | Actual monthly cost against the Rp745,000 fixed budget (business model) |

## 10. Main risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Offline sync loses or duplicates orders | Money and trust | Client IDs, idempotent server, Phase 5 gate with automated tests |
| Commission calculated wrongly | Revenue and disputes | Shared function with tests, server-only, reconciliation in Phase 6 |
| Auto-confirm or block periods never decided | Phase 6 stalls | Code stays off until set; the founder decides before Phase 6 starts |
| Low-end phones too slow | Buyers leave | Device checks at Phases 5 and 8; payload limits; paging |
| Distributors refuse minimum commission | Revenue below plan | Pilot tests it; minimum stays Rp25,000 until the review |
| Agents fake orders | Payouts for nothing | Pay only Confirmed orders with commission paid (BR-11) |
| Legal or tax problems with payments | Fines or forced change | Phase 2 payments only after legal review (BR-09); tax sign-off before first invoice |
| Scope creep | Late pilot | Out-of-scope list (business requirements section 4.2); changes need a spec update first |
| Founder is a bottleneck for approvals | Slow progress | Gates are short; agents prepare the decision and the evidence |
| Vendor price changes | Cost overrun | Cost checkpoints; prices re-checked at each phase |

## 11. Definition of done for the whole build

- Scenarios 1 to 12 pass on staging and on a low-end Android device.
- Every FR-01 to FR-31 has a test traced to it.
- Business rules BR-01 to BR-16 are enforced in code or in the process, with the process written in the runbook.
- Restore from backup is tested and recorded.
- Terms and privacy notice signed off by a lawyer.
- Pilot KPI reporting works from the admin console.
- The founder has signed each gate, and the review checklist is complete for every merged pull request.

## 12. Indicative effort

Estimates are for planning only. Re-estimate after Phase 0 with real measurements.

| Phase | Relative size | Notes |
|---|---|---|
| 0 | S | Mostly setup |
| 1 | M | Correctness-critical; more tests than screens |
| 2 | M | SMS provider integration drives the timing |
| 3 | S to M | Image pipeline is the main effort |
| 4 | L | Largest feature set; both apps and the web |
| 5 | L | Offline and sync are the hardest part to get right |
| 6 | M | Scheduled jobs and reconciliation |
| 7 | M | Admin screens are many but simple |
| 8 | M | Mostly testing, legal and runbook work |
| 9 | S (calendar time) | Four weeks of running the pilot |
| 10 | M to L | Depends on R2 and R3 scope |

Calendar time depends on how much time the founder can give to approvals, and on how many agent sessions run in parallel. Phases 2, 3 and 4 can overlap once Phase 1 has passed its gate, since mobile and web work can proceed against the server contracts.
