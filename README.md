# MitraLink: Papua Distribution Connect

A marketplace where kios, warung, schools and churches in Papua find and order from local distributors. The distributor ships. We earn a commission on each confirmed sale. We do not hold stock, ship goods, or handle buyer money.

**Status:** draft business plan, ready for a four-week test. No app is built yet.

## Documents

- [Business plan](docs/business-plan.md): problem, solution, customers, operations, risks, funding
- [Business model](docs/business-model.md): who pays, commission rates, revenue and costs, break-even
- [Four-week test plan](docs/test-plan.md): targets, weekly routine, tracking sheet, decision rules
- [Terms and conditions](docs/terms-and-conditions.md): draft for buyers, distributors and agents, pending legal review
- [Business requirements](docs/business-requirements.md): business rules, scope, KPIs, open decisions
- [Product spec](docs/product-spec.md): personas, order state machine, functional requirements, screens, data model, acceptance scenarios
- [Agent workflow](docs/agent-workflow.md): how AI agents build the web and mobile apps, phases, gates, review checklist
- [Build plan](docs/build-plan.md): end-to-end plan, phases 0 to 10, exit gates, decisions by phase, testing, risks
- [Decision log](docs/decision-log.md): blocking decisions D-001 to D-012, with options, recommendations and status

## Build status

| Area | Status |
|---|---|
| Repository layout and CI | Done: `.github/workflows/ci.yml` runs type check and tests |
| Shared business rules (`packages/shared`) | Done: money, commission (FR-17), order state machine (product spec section 3), order codes, configuration with undecided values blocked. 31 tests pass. |
| Supabase project and schema (`supabase/`) | Done for development: project `mitralink` created; schema, reference data, row-level security and order functions applied; 32 database checks pass. See `supabase/README.md`. |
| Phase 2 database (registration, approval) | Done for development: buyer, agent and distributor registration, admin approval and rejection, distributor documents. 22 database checks pass. Phone sign-in waits for D-001. |
| Phase 3 database (catalogue) | Done for development: add, change and show products, restricted-goods rule, 300 KB photo limit, town catalogue, admin hide and unhide. 22 database checks pass. Photo storage bucket and app compression come with the apps. |
| Phase 6 database, invoices part (weekly invoices, payment marking, overdue block) | Done for development: weekly invoices, mark paid, overdue list, tax number recorded, overdue block gated on D-007. 20 database checks pass. Agent payouts and auto-confirm wait for D-006 and D-008. |
| Phase 7 database (admin and reporting) | Done for development: validated configuration changes (audited), category change audit, KPI report against the test targets, audit viewer, admin distributor block, user suspension, agent payouts (refuse until D-008 is decided), scheduled daily and weekly jobs with KPI snapshots. 42 database checks pass across the two Phase 7 tests. |
| Phase 5 database (offline sync) | Done for development: `sync_action` for queued actions (applied once, conflicts reported, never silent), sync log, PowerSync publication, draft sync rules in `powersync/`. 15 database checks pass. PowerSync project and dashboard validation wait for the account. |
| Phase 4 database (ordering and fulfilment) | Done for development: decline and cancel reasons, automatic AwaitingPayment, payment instructions, proof photos, payment reversal, dispute photos, notification queue. 23 database checks pass. SMS sending waits for D-001. |
| Starter Bahasa Indonesia strings | Done: `strings/id.json`, pending native-speaker review |
| Supabase staging and production projects | Not started: create after the pilot schema is reviewed |
| Mobile app (Expo, `apps/mobile`) | Scaffold done, runs locally: home and Jayapura catalogue screens; bundles for Android. Sign-in, basket and offline sync still to build. |
| Web dashboard (Next.js, `apps/web`) | Scaffold done, builds: home, admin KPI report, admin approvals. Sign-in still to build. |
| Decisions D-001 to D-012 | Open: see `docs/decision-log.md` |

Run locally: `npm install`, then `npm run typecheck` and `npm test`.

## Claude Code skills

- [`mitralink-spec`](.claude/skills/mitralink-spec/SKILL.md): trace a request to business rules before coding
- [`mitralink-build`](.claude/skills/mitralink-build/SKILL.md): build rules for money, state, security, offline and language
- [`mitralink-review`](.claude/skills/mitralink-review/SKILL.md): review a change against the specs

## Summary

| Item | Value |
|---|---|
| Buyer cost | Rp0 |
| Commission | 1.5–3% by category, Rp25,000 minimum per order |
| Monthly fixed costs (launch) | About Rp745,000 |
| Break-even (no agent fee) | About 33 confirmed orders a month |
| Break-even (Rp5,000 agent fee per order) | About 41 confirmed orders a month |
| Capital for the test | About Rp0 (phone, WhatsApp, spreadsheet) |

All rates, minimums and prices are assumptions to test. Sources cited in the business plan were not re-checked.
