---
name: mitralink-spec
description: Use before writing or changing any MitraLink feature, to trace the request to business rules (BR-xx) and functional requirements (FR-xx), check acceptance criteria exist, and stop on open decisions. Use for any request that adds or changes ordering, payment marking, shipping, confirmation, commission, invoices, agent payouts, roles, notifications or offline sync.
---

# MitraLink spec check

Run this before any code is written. The specs are the source of truth:

- `docs/business-requirements.md`: business rules BR-01 to BR-16, open decisions
- `docs/product-spec.md`: functional requirements FR-01 to FR-31, order state machine, permissions, data model, commission logic, acceptance scenarios
- `docs/agent-workflow.md`: phases, gates and the review checklist

## Steps

1. **Find the requirement.** Search the product spec for the feature. Quote the FR-xx and BR-xx IDs that apply. If none apply, the request is out of scope: say so and stop, or propose a spec change.
2. **Check the acceptance criteria.** Each FR lists them. Confirm they are complete enough to test. If they are missing, write them into the product spec and ask the founder to approve before building.
3. **Check the business rules.** Does the request conflict with any BR? Key guards:
   - Money and commission are server-side only (BR-04, FR-17).
   - Ship only after PAID (BR-05).
   - Only Confirmed orders count (BR-07).
   - Platform never holds buyer money in the test (BR-09). Phase 2 payment work needs legal review first.
   - Minimum commission is Rp25,000 per order and currently stays there (BR-02).
   - Agents and buyers cannot mark PAID or SHIP (BR-12).
4. **Check open decisions.** Business requirements section 10 lists decisions not yet made, such as the auto-confirm period, the block period, the agent fee and the stack choice. If the request depends on one, stop and ask. Do not pick a value.
5. **Check the state machine.** If the feature changes order state, the transition must appear in product spec section 3. Any new transition needs a spec change first.
6. **Check permissions.** Use the matrix in product spec section 6. Every new action needs a role.
7. **Report back** in this format:

```
Requirement: FR-xx (name), BR-xx, BR-yy
Acceptance criteria: present / missing (list what is missing)
Conflicts: none / list
Open decisions blocking: none / list
Affected areas: backend / mobile / web / docs
Next step: proceed to plan / ask founder: <question>
```

## Stop and ask when

- a rule must change (BR or FR) to support the request;
- the request touches commission rates, minimums or periods;
- the request adds handling of buyer money or a payout from MitraLink;
- the request stores personal data with a new third party;
- an open decision is needed to finish the work.

Do not guess the answer. Do not build a version "to be changed later".
