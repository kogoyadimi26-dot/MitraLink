---
name: mitralink-review
description: Use to review a MitraLink pull request or diff against the specs before it is marked ready. Checks traceability to requirement IDs, business rules, money and state logic on the server, row-level security, offline behaviour, audit logging, secrets and language. Use when asked to review, check, or sign off MitraLink changes.
---

# MitraLink review

Review against the specs, not personal taste. The checklist in `docs/agent-workflow.md` section 7 is the standard.

## Steps

1. **Read the description.** Confirm it lists requirement IDs (BR-xx, FR-xx). If not, request them.
2. **Map the diff to the spec.** For each changed area, name the requirement it implements. Flag changes with no requirement.
3. **Check money.**
   - Commission calculated only on the server.
   - Integer rupiah only; no float arithmetic on money.
   - Minimum Rp25,000 per order applied as specified (product spec section 8).
   - Tests cover the two examples in FR-17.
4. **Check state.**
   - Transitions go through the single state function.
   - Each transition is in the allowed table (product spec section 3).
   - SHIP is blocked unless PAID. RECEIVED is only set by the buyer.
   - An `OrderEvent` is written.
5. **Check security.**
   - RLS enabled for new tables; policies per role match the permissions matrix (product spec section 6).
   - No service keys in client code.
   - No bank numbers, phone numbers or personal data in logs or fixtures.
6. **Check offline and idempotency.**
   - Retried actions carry a client ID; the server handles duplicates.
   - UI shows pending state until the server confirms.
7. **Check audit.** Money, state, invoice, payout and configuration changes write audit rows. The audit log has no update or delete path.
8. **Check language and UI.** Strings in Bahasa Indonesia from the string file; touch targets at least 44 px; amounts and dates formatted correctly.
9. **Check tests.** Each linked acceptance criterion has a test. Failing tests are not disabled. Include the test output.
10. **Check spec drift.** If a rule changed in code, the business requirements or product spec must change in the same pull request.

## Output format

```
Verdict: ready / changes requested / blocked
Traceability: FR-xx, BR-xx covered; uncovered changes: ...
Blocking issues:
  - file:line — problem — which rule it breaks
Non-blocking notes:
  - ...
Tests: X passed, Y failed (paste output summary)
Open decisions touched: none / list
```

Use `file_path:line_number` references so the author can navigate directly.

## Blocking issues (always)

- Commission or money calculated on the client, or with floats.
- A state transition not in the allowed table, or a SHIP without PAID.
- A table without RLS, or a policy that lets one user read another's orders.
- A retried action that can create duplicates.
- A money or state change without an audit event.
- A disabled or deleted failing test.
- A business rule changed without a spec change.
- Secrets or real personal or bank data in the diff.

## Do not

- Approve or merge. The founder decides.
- Suggest a rate, minimum or period change. Those are open decisions.
- Comment on the pull request unless asked. Report in the conversation instead.
