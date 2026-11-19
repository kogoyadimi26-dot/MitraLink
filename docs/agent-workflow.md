# Agent workflow: building MitraLink

This document describes how AI agents (Claude Code and sub-agents) build the MitraLink web dashboard and mobile app. It is the process every agent follows. The product rules live in the [business requirements](business-requirements.md) and the [product spec](product-spec.md). The Claude Code skills that enforce this workflow are in [`.claude/skills/`](../.claude/skills/).

## 1. Principles

1. **Specs before code.** No feature is built unless it traces to a requirement ID (BR-xx or FR-xx).
2. **Money and state are server-side.** Commission, order state and invoices are calculated and enforced on the server. The app never decides them.
3. **One source of truth.** Business rules are changed in the business requirements first, then in code. Code never silently diverges.
4. **Small, reviewable steps.** One feature per branch and pull request, with tests.
5. **Ask when a decision is missing.** Open decisions (business requirements section 10) are not guessed. The agent stops and asks.
6. **Respect the constraints.** Offline-first, low-end Android, small payloads, Bahasa Indonesia.

## 2. Roles

| Agent role | Responsibility | Writes to | Must not |
|---|---|---|---|
| **Spec agent** | Turns a request into a traceable change to the specs. Flags conflicts with business rules. | `docs/` | Write application code |
| **Backend agent** | Database schema, row-level security, server functions, commission and state logic, sync endpoints | `backend/`, `supabase/` (or chosen backend) | Change business rules |
| **Mobile agent** | Mobile screens, offline queue, local database, notifications | `mobile/` | Calculate commission or set order state locally |
| **Web agent** | Distributor dashboard, admin console, reports | `web/` | Bypass server checks for money or state |
| **QA agent** | Writes and runs tests against the acceptance scenarios; reviews diffs against the rules | `tests/`, test reports | Change code to make tests pass without a stated reason |
| **Review agent** | Checks a pull request against the checklist (section 7) | Review comments only | Merge or push to main |

A single Claude Code session may play several roles in turn, but each change should be clearly labelled with its role in the commit or pull request.

## 3. Phases and gates

Each feature moves through these phases. A gate must pass before the next phase starts.

### Phase 1: Specify
- Spec agent confirms the requirement ID(s) and acceptance criteria exist.
- If not, the spec agent writes them first and asks the founder to approve.
- **Gate:** requirement has an ID, acceptance criteria, and no open decision blocking it.

### Phase 2: Plan
- Agent lists files to change, data model changes, API or server functions, and tests.
- Agent names any risk to money, state or security.
- **Gate:** plan lists tests for every acceptance criterion. Changes to the data model or to money logic are shown to the founder before work begins.

### Phase 3: Build
- Backend first when the feature changes data or rules. Then mobile or web.
- Each commit is small and passes tests on its own.
- Agent does not change business rules, the state machine or commission logic without updating the specs in the same change.
- **Gate:** unit tests pass; server rules have tests; no secrets in code.

### Phase 4: Test
- QA agent runs the acceptance scenarios that the feature touches (product spec section 14).
- Offline behaviour is tested by turning off the network in the test device or emulator.
- Low-end device checks are run before each release candidate.
- **Gate:** all linked acceptance criteria pass. Failures are reported with output, not hidden.

### Phase 5: Review and merge
- Review agent checks the pull request against section 7.
- Pull request is a draft until all gates pass, then marked ready for the founder to merge.
- **Gate:** checklist complete; founder approves.

## 4. Handoffs

Agents hand work to each other through files, not memory.

| Handoff | Artifact | Location |
|---|---|---|
| Spec to plan | Requirement IDs and acceptance criteria | `docs/product-spec.md` |
| Plan to build | Plan checklist in the pull request description | Pull request |
| Backend to mobile and web | API contract and data model | `docs/api/` (created by backend agent) |
| Build to test | Test list mapped to acceptance criteria | `tests/README.md` |
| Test to review | Test report with output | Pull request comment (no secrets) |

If the API contract changes after mobile or web has started, the backend agent updates the contract and flags the change in the pull request.

## 5. Stack defaults

Defaults until the founder decides otherwise (business requirements section 10, item 5):

| Layer | Default | Alternative |
|---|---|---|
| Mobile app | React Native with Expo | Flutter |
| Web dashboard | Next.js (TypeScript) | Any React framework |
| Backend and database | Supabase (Postgres, auth, storage, edge functions) | Self-hosted Postgres with a custom API |
| Offline sync | PowerSync | Custom outbox endpoint |
| Notifications | SMS provider, later WhatsApp Business via a provider | (to decide) |
| Payments (Phase 2) | Licensed gateway with split payouts | (to decide after legal review) |

Pin dependency versions. Commit lock files. Do not add a dependency without a reason written in the pull request.

## 6. Working rules

### Repository and branches
- Work on the feature branch named in the session. Do not push to other branches without permission.
- One feature per branch. Name branches `feature/<req-id>-short-name`, for example `feature/FR-17-commission`.
- Pull requests are drafts until the gates pass.
- Commit messages describe the change and the requirement ID. Include the attribution lines the session asks for.

### Secrets and data
- Never commit keys, passwords, bank account numbers or real customer data.
- Use environment variables and secret stores. Provide an `.env.example` with placeholder values.
- Test data is fictitious. Names and phone numbers in fixtures must not be real.

### Money and state
- Money is integer rupiah (BR-15). Never use floating-point for money.
- Commission is calculated only in server code and covered by tests for the examples in the product spec (FR-17, section 8).
- Order state changes go through the state machine in the product spec (section 3). Any transition not listed is rejected.
- Every state or money change writes an audit event (BR-13).

### Offline
- Mobile writes go to the local outbox first, with a client ID.
- The server enforces idempotency on client IDs.
- UI shows pending state. Never show an order as sent until the server confirms it.

### Language and content
- User-facing text is in Bahasa Indonesia, stored in one string file.
- Do not hard-code amounts or dates in text; format them with the shared helpers.

### Dependencies and performance
- Images are compressed before upload.
- Lists are paged. No loading of the full catalogue at once.
- Measure app size and cold start on a low-end Android device before each release.

## 7. Review checklist

A pull request is ready for merge only when every item is checked.

- [ ] Traces to requirement IDs (BR or FR) listed in the description
- [ ] Acceptance criteria covered by tests
- [ ] No business rule changed without a matching change to the business requirements
- [ ] Commission and state logic only on the server; tests for the minimum-fee example
- [ ] Money stored as integer rupiah
- [ ] Row-level security covers new tables and endpoints
- [ ] Offline behaviour tested for any action a buyer or agent can take
- [ ] Idempotency for any action that can be retried
- [ ] Audit event written for money or state changes
- [ ] No secrets, real personal data or bank numbers in code, fixtures or logs
- [ ] User-facing text in Bahasa Indonesia, from the string file
- [ ] Touch targets at least 44 px; labels next to icons
- [ ] Payload sizes checked for any new endpoint or image
- [ ] Dependencies pinned, with a reason for each new one
- [ ] Test report attached

## 8. What agents must stop and ask about

Stop and ask the founder before:

- changing any business rule (BR-xx) or open decision;
- changing commission rates, minimums, block periods or auto-confirm periods, even in configuration defaults;
- adding any feature that handles buyer money, including a gateway, a wallet or a payout from MitraLink to distributors;
- storing or sending personal data to a new third party;
- adding a new paid service or changing the monthly cost estimate;
- deleting data, or changing the audit log;
- pushing to a branch other than the feature branch, merging, or changing production settings.

## 9. Definition of done

A feature is done when:

1. Its requirement IDs are traced in the pull request.
2. Its acceptance criteria pass in tests, including the relevant end-to-end scenarios.
3. The review checklist is complete.
4. It works on a low-end Android device for mobile changes, or in the supported browsers for web changes.
5. Docs are updated if behaviour or rules changed.
6. The founder has reviewed and approved the pull request.

## 10. Failure handling

- If tests fail, the agent reports the failing test and output. It does not disable or skip the test to get green.
- If a rule in the specs seems wrong, the agent raises it as a question with the requirement ID and a suggested change. It does not work around the rule.
- If a dependency or service is unavailable, the agent records the blocker and continues with work that does not depend on it.
