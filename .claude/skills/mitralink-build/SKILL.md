---
name: mitralink-build
description: Use when building or changing MitraLink code (backend, mobile app, web dashboard) after the spec check. Covers stack defaults, server-side money and state logic, offline-first behaviour, row-level security, idempotency, audit logging, Bahasa Indonesia strings and low-end Android constraints.
---

# MitraLink build

Read these first, in order:

1. `.claude/skills/mitralink-spec/SKILL.md`: confirm the requirement and acceptance criteria exist.
2. `docs/agent-workflow.md`: phases, gates, working rules.
3. `docs/product-spec.md`: the feature's FR-xx, state machine, data model, commission logic.

Work in phases: plan, build, test, review. Do not skip the plan for data or money changes.

## Stack defaults

Use the stack in `docs/agent-workflow.md` section 5, which the founder has decided:

- Mobile: React Native with Expo, TypeScript.
- Web: Next.js, TypeScript.
- Backend: Supabase (Postgres, auth, storage, edge functions).
- Offline sync: PowerSync, or a custom outbox endpoint if rejected.

Pin versions and commit lock files.

## Hard rules

### Money
- Store every amount as integer rupiah. Never use floats.
- Compute commission only on the server, using the rule in product spec section 8:
  `commission = max(round(order_value × rate_bp / 10000), 25000)`.
- Store each order's commission lines with the rate used, so the figure can be reproduced.
- Test the examples: Rp1,000,000 staples gives Rp25,000; Rp2,000,000 electronics at 2% gives Rp40,000.

### State
- Order state changes go through a single server function that checks the allowed transitions in product spec section 3.
- Reject any transition not in the table, with a clear error.
- Write an `OrderEvent` row for every transition (who, when, device, from, to).
- A distributor cannot set SHIP unless the order is Paid. A buyer alone sets RECEIVED.

### Security
- Enable row-level security on every table. Each user reads and writes only their own rows (NFR-06).
- Test RLS for each role: buyer, agent, distributor, admin.
- Keep keys in environment variables. Never commit `.env` files.
- Upload files through signed URLs with size and type checks.
- Never log bank account numbers, phone numbers or personal details in plain text.

### Idempotency
- Every action that can be retried carries a client-generated ID.
- The server stores processed IDs and returns the original result on a repeat (NFR-03).

### Audit
- Every money or state change, invoice payment, payout and configuration change writes to `AuditLog` (BR-13).
- The audit log is append-only. No update or delete policies.

### Offline (mobile)
- Writes go to the local outbox first. The UI shows "Menunggu sinkron" until the server confirms.
- Cache the catalogue, the user's orders and the last 30 days of history (FR-31).
- Show sync status (FR-30). Show conflicts to the user (FR-29); never merge silently.
- Test each buyer and agent action with the network off.

### Language and UI
- All user text is in Bahasa Indonesia, from the shared string file.
- Amounts: `Rp1.000.000`. Dates: `2 Des 2026`.
- Touch targets at least 44 px. Labels next to icons.
- Lists are paged. Images are compressed before upload (target under 300 KB, FR-08).

### Performance and devices
- Target a 2 GB RAM Android phone for mobile changes (NFR-07).
- Do not add a dependency without a reason in the pull request. Prefer what the stack already provides.

## Screens

Use the screen lists in `docs/product-spec.md` section 5. Do not add screens or actions that are not in the spec. If a screen seems missing, use the spec check skill to raise it.

## Checklist before handing to review

- [ ] Requirement IDs listed in the pull request description
- [ ] Money as integer rupiah; commission only on the server
- [ ] State transitions only through the server function; events written
- [ ] RLS on new tables; role tests written
- [ ] Idempotency on retried actions
- [ ] Audit events on money and state changes
- [ ] Offline behaviour tested for buyer and agent actions
- [ ] Bahasa Indonesia strings; touch targets; payload sizes
- [ ] No secrets, real data or bank numbers in code or fixtures
- [ ] Tests pass. Report the output, and do not disable any failing test.

Use `.claude/skills/mitralink-review/SKILL.md` for the full review.
