# Decision log

Records each decision that blocks a build phase, with the options considered, the recommendation, and the final decision once made. Decisions are changed by adding a new entry that supersedes the old one. Do not edit a decided entry's outcome in place.

**Status values:** Open (no decision yet), Proposed (recommendation written, awaiting founder), Decided, Superseded.

**Owner:** the person who makes the decision. "Founder" means the business owner.

## Summary

| ID | Decision | Blocks phase | Status | Recommendation | Owner |
|---|---|---|---|---|---|
| D-001 | SMS provider | 2 | Proposed | Local Indonesian provider with direct operator routes, chosen after delivery tests in Wamena | Founder |
| D-002 | SMS sender name | 2 | Proposed | Register a sender name early; check current registration rules | Founder |
| D-003 | Distributor document types | 2 | Proposed | NIB, NPWP, company deed, owner ID, bank proof, location photo | Founder with lawyer |
| D-004 | Launch towns | 3 | Proposed | Jayapura and Wamena only | Founder |
| D-005 | Restricted goods list | 3 | Proposed | Conservative starting list, with admin approval per category | Founder with local lawyer |
| D-006 | Auto-confirm period | 6 | Proposed | 7 days after SHIP, reminder on day 5 | Founder |
| D-007 | Overdue block period | 6 | Proposed | Block when an invoice is more than 7 days overdue; reminders on days 3 and 6 | Founder |
| D-008 | Agent fee | 6 | Proposed | Rp5,000 per confirmed order for the test; review at week 4 | Founder |
| D-009 | Tax treatment and invoice fields | 6 | Open | Written opinion from an Indonesian tax consultant before the first real invoice | Tax consultant, then founder |
| D-010 | On-time KPI window | 7 | Proposed | Measure "confirmed within 3 days of delivery" separately from the auto-confirm period | Founder |
| D-011 | Legal sign-off on terms and privacy | 8 | Open | Written review by an Indonesian lawyer | Lawyer, then founder |
| D-012 | Data retention periods | 8 | Open | Tax and audit records 10 years, short login logs, delete after account closure | Lawyer with tax consultant |

## Entry template

Each entry uses these fields:

- **Question:** what must be decided
- **Blocks:** the build phase and the requirements affected
- **Options considered:** with a short trade-off for each
- **Recommendation:** what I suggest and why
- **Evidence needed:** what must be checked before deciding
- **Status and decision:** the final answer, with the date and the person who decided
- **Consequences:** what changes in the specs or the build once decided

## Phase 2: Identity and onboarding

### D-001: SMS provider

- **Question:** which provider sends login codes and order notices by SMS?
- **Blocks:** Phase 2 login (FR-01); Phase 4 notices (FR-24)
- **Options considered:**
  - Local Indonesian provider with direct operator routes. Better delivery, usually local support. Need to verify contract terms.
  - International aggregator. Easier setup, but OTP delivery to Papuan operators can be slow or blocked.
  - Own gateway with a modem. Full control, but a large operational burden. Not suitable for a small team.
- **Recommendation:** local provider with direct routes. Choose after testing delivery to Telkomsel and XL numbers in Wamena and Jayapura.
- **Evidence needed:** delivery test results (time to deliver, failure rate) from at least two providers; price per message; sender name registration process and time; contract minimums.
- **Status and decision:** Proposed. Awaiting founder choice and test results. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** update FR-01 with the chosen provider; add the provider's API to the Phase 2 backlog; record the per-message cost in the business model.

### D-002: SMS sender name

- **Question:** what name appears as the sender of login codes and notices?
- **Blocks:** Phase 2 login (FR-01)
- **Options considered:**
  - A short business name, such as the MitraLink brand. Clear to buyers, but must be registered and approved.
  - A generic provider sender. Quicker, but buyers may not trust it.
- **Recommendation:** register "MitraLink" as the sender name as soon as the provider is chosen, and allow time for approval.
- **Evidence needed:** the current sender registration rules and expected approval time, confirmed by the provider.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** update the SMS templates in FR-24 and the Bahasa Indonesia string file.

### D-003: Distributor document types

- **Question:** which documents must a distributor provide before approval?
- **Blocks:** Phase 2 distributor approval (FR-03)
- **Options considered:**
  - Full list (NIB, NPWP, deed, owner ID, bank proof, location photo, product licences where needed). Stronger checks, fewer distributors sign up.
  - Minimal list (NPWP and owner ID). Faster onboarding, weaker checks against fraud.
  - Tiered approval: minimal documents to start, full set before the first payout. More work for admin.
- **Recommendation:** full list for the first distributors, since there are only 3 to 5 in week 1 and trust matters most early on.
- **Evidence needed:** the lawyer's view on the required documents for a distributor selling goods in Papua; check that each document can be obtained by a small shop.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** the list becomes the approval checklist for admin; FR-03 is updated with the final list.

## Phase 3: Catalogue

### D-004: Launch towns

- **Question:** which towns are live at launch?
- **Blocks:** Phase 3 catalogue and town filter (FR-06); order code prefixes (product spec section 9)
- **Options considered:**
  - Jayapura and Wamena only. Matches the test plan; agents and distributors already identified.
  - Add Nabire or Timika at launch. Wider reach, but more distributors and agents to recruit before the pilot can start.
- **Recommendation:** Jayapura and Wamena only, as the plan says. Add towns after the pilot passes its gate.
- **Evidence needed:** the list of distributors and agents confirmed in each town.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** seed the town table with codes `J` and `W`; order codes use these prefixes.

### D-005: Restricted goods list

- **Question:** which goods cannot be listed by distributors?
- **Blocks:** Phase 3 publish rules (FR-07, BR-08); terms section 5.3
- **Options considered:**
  - Conservative list with admin review for every new category. Lower risk, slower to add products.
  - Broad list that follows national rules only. Fewer restrictions, but misses local rules.
- **Recommendation:** start with alcohol, firearms and explosives, prescription medicines and controlled substances, counterfeit goods, live animals and protected species, and tobacco sold to minors. Add admin review for any category not on the list. Have a local lawyer check against Papua regional rules.
- **Evidence needed:** lawyer's review of the list against national and Papua regional rules; check of the local government's list of restricted goods.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** the list is stored as configuration with a version number; the terms section 5.3 is updated to match.

## Phase 6: Commission, invoices and payouts

### D-006: Auto-confirm period

- **Question:** how long after SHIP does an order confirm automatically if the buyer does not reply?
- **Blocks:** auto-confirm (FR-14, BR-06); reminders (FR-25); scenario 7
- **Options considered:**
  - 3 days after SHIP. Matches the on-time KPI window, but confirms orders before buyers have received them on slow routes.
  - 7 days after SHIP. Allows for slow delivery in Papua.
  - 14 days after SHIP. Safest for buyers, but delays commission and makes the ledger slower to close.
- **Recommendation:** 7 days after SHIP, with a reminder on day 5. Keep the 3-day on-time KPI as a separate measure (D-010).
- **Evidence needed:** typical delivery times from distributors to buyers in Jayapura and Wamena, measured during the test.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** set the configuration value; enable auto-confirm in Phase 6 only when the value is set (build plan section 6).

### D-007: Overdue block period

- **Question:** when does a distributor's unpaid invoice block new orders?
- **Blocks:** overdue block (FR-19, BR-10); scenario 8
- **Options considered:**
  - Block at 7 days overdue. Matches the 7-day payment term.
  - Block at 14 days overdue. More time for distributors, more exposure for MitraLink.
  - Block at the first day overdue. Strict, may stop distributors over a bank delay.
- **Recommendation:** payment due in 7 days (terms section 6.3). Block new orders when an invoice is more than 7 days overdue. Remind on day 3 and send a final notice on day 6.
- **Evidence needed:** founder's view on how much risk to carry during the pilot.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** set the configuration value; add the reminder schedule to FR-25.

### D-008: Agent fee

- **Question:** how much does MitraLink pay an agent per confirmed order?
- **Blocks:** agent payouts (FR-22, BR-11); scenario 10
- **Options considered:**
  - Rp5,000 per confirmed order. Matches the business model. Break-even about 41 orders a month.
  - Rp3,000 per confirmed order. Lower cost, break-even about 36 orders a month, but may weaken agent motivation.
  - Rp5,000 with a repeat-order bonus later. More complex; decide after the pilot.
- **Recommendation:** Rp5,000 per confirmed order for the test. Review at week 4.
- **Evidence needed:** agent interviews during recruitment; confirmation of tax treatment (D-009).
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** set the configuration value; update the agent terms (terms section 7.2).

### D-009: Tax treatment and invoice fields

- **Question:** how is commission taxed, which invoice format is used, and how are agent payments taxed?
- **Blocks:** invoice fields (FR-20, BR-16); first real invoice; agent payouts (FR-22)
- **Options considered:**
  - Written opinion from an Indonesian tax consultant. Required before the first real invoice.
  - Self-assessment without advice. Not recommended; risk of penalties.
- **Recommendation:** hire a tax consultant (konsultan pajak). Ask for a written answer on: final 0.5% tax on turnover under PP 55/2022 and its eligibility period; whether commission is subject to VAT (PPN), at what current rate, and whether registration as a taxable entrepreneur (PKP) is needed; invoice format, including e-Faktur if it applies; withholding on agent payments and the forms agents must provide; recording of income and costs.
- **Evidence needed:** the business model, commission table, invoice template and agent terms sent to the consultant. All current rates to be confirmed by the consultant, not from this log.
- **Status and decision:** Open. Consultant engaged: [ ]. Written opinion received: [ ]. Decision date: [ ].
- **Consequences once decided:** update the invoice fields in FR-20; update the agent payout calculation; file the opinion in `docs/legal/` (not in the repository if it contains personal data).

### D-010: On-time KPI window

- **Question:** what counts as an order confirmed "on time" for the 80% target?
- **Blocks:** the KPI report (FR-27); the success target in the test plan
- **Options considered:**
  - Confirmed within 3 days of delivery. Measures buyer behaviour directly.
  - Confirmed before the auto-confirm period. Counts auto-confirmed orders as on time, which overstates the figure.
- **Recommendation:** measure "confirmed within 3 days of SHIP or delivery, whichever the distributor records" as the KPI. Report auto-confirmed orders separately.
- **Evidence needed:** founder's agreement to the definition before the test starts.
- **Status and decision:** Proposed. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** update the KPI definition in the business requirements and the test plan, and the report in FR-27.

## Phase 8: Legal and data

### D-011: Legal sign-off on terms and privacy

- **Question:** do the terms, privacy notice and agent and distributor agreements meet Indonesian law for the launch model?
- **Blocks:** pilot release (Phase 8 exit); terms acceptance at registration (FR-02)
- **Options considered:**
  - Indonesian lawyer (advokat) with e-commerce and personal data experience. Recommended.
  - Standard online templates without review. Not recommended for a launch that handles payments and personal data.
- **Recommendation:** engage an advokat to review the terms (`docs/terms-and-conditions.md`), the privacy notice, the distributor commission agreement and the agent agreement. Ask for a short written opinion on the test model, which holds no buyer money.
- **Evidence needed:** the terms with placeholders filled in; the data flow description; the list of personal data fields.
- **Status and decision:** Open. Lawyer engaged: [ ]. Written review received: [ ]. Decision date: [ ].
- **Consequences once decided:** update the terms version; record the version accepted at registration (FR-02); add the agreed wording to the privacy notice.

### D-012: Data retention periods

- **Question:** how long is each category of personal and business data kept, and when is it deleted?
- **Blocks:** Phase 8 exit; data deletion requests (BR-14, FR-02)
- **Options considered:**
  - Tax and audit records kept 10 years; other data deleted when no longer needed. Balances tax rules with data minimisation.
  - Keep everything indefinitely. Simpler, but conflicts with data minimisation.
  - Delete everything at account closure. Not possible for tax records.
- **Recommendation (starting point, to be confirmed by lawyer and tax consultant):**

  | Data | Retention |
  |---|---|
  | Accounting and tax records (invoices, orders, commission, payment evidence) | 10 years |
  | Audit log | Same as tax records |
  | Active account data | While the account is active |
  | Closed account data (not tax records) | Delete or anonymise after a fixed period, for example 90 days |
  | SMS and login logs | Short, for example 90 days |
  | Dispute photos | Until the dispute closes, then delete after a set period |

- **Evidence needed:** the tax consultant's view on the retention period for tax records; the lawyer's view under the personal data law.
- **Status and decision:** Open. Decision date: [ ]. Decided by: [ ].
- **Consequences once decided:** add retention tags to tables (product spec section 11); build the deletion and anonymisation job; add the periods to the privacy notice.

## Change history

| Date | Change | By |
|---|---|---|
| [date] | Log created with recommendations for D-001 to D-012 | Claude Code session |
