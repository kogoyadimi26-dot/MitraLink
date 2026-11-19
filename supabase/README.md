# Supabase: database

Project: `mitralink` (Singapore region, ap-southeast-1), in the existing Supabase organization. Created for Phase 0 and Phase 1 of the [build plan](../docs/build-plan.md). The project is a development project. Staging and production projects come later.

## Migrations

Applied in order. Each file is the final state for its area.

| File | Contents |
|---|---|
| `migrations/20261119000001_core_tables.sql` | Enums, all tables from product spec section 7, constraints, indexes |
| `migrations/20261119000002_reference_data.sql` | Towns J and W (active), categories and rates, Rp25,000 minimum, transition rules |
| `migrations/20261119000003_security_rls.sql` | Row-level security on every table, helper functions, grants, append-only audit and event tables |
| `migrations/20261119000004_business_functions.sql` | `place_order`, `transition_order`, commission, order codes, restricted-goods guard, config audit |

Two fixes were found by testing and the security advisor and applied as separate migrations in the project. They are already included in files 003 and 004 here:

- The `place_order` agent check returned NULL for buyers with no agent, so an agent could order for another agent's buyer. Fixed with an explicit null-safe test.
- Supabase grants new functions to `anon` by default. `place_order` and `transition_order` are now revoked from `anon`.

## Undecided values are not seeded

Auto-confirm period (D-006), overdue block period (D-007) and agent fee (D-008) are deliberately absent from `config`. Code that needs them must fail until the founder decides. See [decision log](../docs/decision-log.md).

## Tests

`tests/db_rules.sql` runs the order path, the actor rules, guards, commission, audit, configuration audit and row-level security. It creates test users and orders, and ends by raising an error that carries the results, so every change is rolled back. Run it only on a development project.

Last run: 32 of 32 checks passed.

## Security advisor

Remaining advisor notes, all expected:

- `client_actions` and `town_sequences` have RLS enabled and no policies. This is intended: only security-definer functions use them.
- `current_role_name`, `is_admin`, `place_order` and `transition_order` can be run by signed-in users. The first two are needed by the row-level security policies. The last two are the intended entry points, and they check ownership and state themselves.

## Notes for future migrations

- Supabase gives `anon` privileges on new tables and functions by default. Any new function that should not be public needs an explicit `revoke ... from anon`.
- Money is whole rupiah. Rates are basis points.
- Orders change state only through `transition_order`. Do not write to `orders.state` directly.
