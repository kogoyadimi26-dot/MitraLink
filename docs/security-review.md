# Security and performance review (Phase 8, database)

Status: review of the development project, after the Phase 1 to 7 database work. Run again on staging and production before the pilot.

## Access control

- **Row-level security:** enabled on all 30 public tables. Each table has a policy for who may read it, or no policy at all, which blocks everyone.
- **Direct writes:** orders, payments, shipments, confirmations, disputes, invoices, payouts, products, notifications and the audit log change only through functions. Users have no direct write access to these tables.
- **Append-only history:** audit log, order events and the sync log cannot be updated or deleted by any role.
- **Anonymous access:** revoked from all tables and from all functions.
- **Scheduler and admin-only jobs:** scheduler functions (run_scheduled_jobs, take_kpi_snapshot, apply_distributor_blocks) are no longer callable by signed-in users. Each one also checks for admin inside.
- **Suspended users:** refused by the nine functions that act for a user (assert_account_active).

## Findings and what was done

| Finding | Action |
|---|---|
| Scheduler functions callable by signed-in users | Revoked from the authenticated role (migration 12) |
| Row-level security re-checked the user id for every row (18 policies) | Rewritten to evaluate once per query (migration 12) |
| 28 foreign keys without an index | Indexes added (migration 12) |
| Security-definer functions callable by signed-in users (33) | Kept on purpose. Each checks the caller's role or ownership inside, and the helpers are needed by row-level security |
| Overlapping admin and read policies on some tables | Kept. Small performance cost; rewriting them would make the write rules harder to read |
| Unused indexes (32) | Kept. New indexes support foreign-key lookups at pilot scale, and the dev project has no traffic yet |
| Sync and client-action tables with no policies | Intended. Only security-definer functions use them |

## Tests

- Database tests: db_rules (31), phase2_onboarding (22), phase3_catalogue (22), phase4_ordering (23), phase5_sync (15), phase6_invoices (20), phase7_admin (21), phase7_completion (21). Each one rolls back its data.
- Regression after the policy change: the access-rule checks (order visibility, distributor bank details, direct inserts, the scheduler) pass 13 of 13.

## Still to do before the pilot

- Re-run the advisors and the database tests on staging.
- Restore a production backup into staging and check it (NFR-09).
- Check the SMS sender and phone sign-in settings in Supabase (D-001).
- Confirm the data retention periods with the lawyer (D-012).
- Decide whether signed-in users who are suspended may still read their own data (today they can; only actions are refused).
