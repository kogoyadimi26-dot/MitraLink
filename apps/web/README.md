# MitraLink web dashboard

Next.js (App Router, TypeScript). Used by distributors and the admin team. Admin and distributor screens are built, with phone sign-in at /masuk.

## Run locally

1. From the repository root: `npm install`
2. Copy `apps/web/.env.example` to `apps/web/.env.local` and fill in the dev project's URL and publishable key.
3. `npm run dev --workspace @mitralink/web`, then open http://localhost:3000

## Pages

Admin (`/admin`):
- `/admin/kpi`: KPI report from `kpi_report`, for any period
- `/admin/approvals`: approve or reject pending distributors (`approve_distributor`, `reject_distributor`)
- `/admin/orders`: filter orders; cancel an order awaiting payment; reverse a payment (`transition_order`, `admin_reverse_payment`)
- `/admin/invoices`: create commission invoices for a period, see overdue invoices, mark invoices paid (`generate_weekly_invoices`, `overdue_invoices`, `mark_invoice_paid`)
- `/admin/audit`: search the audit log (`admin_search_audit`)

Distributor (`/distributor`):
- `/distributor/orders`: accept or decline new orders, mark paid with the bank reference, mark shipped (`transition_order`)
- `/distributor/products`: add products, change prices, show or hide products (`add_product`, `update_product`, `set_product_availability`)
- `/distributor/invoices`: commission invoices and their status (read only)

Every page sits behind `RoleGate`, which only decides what to show. The database enforces the rules.

Sign-in is at `/masuk`: a phone number, then a one-time code by SMS. The session is kept in the browser. Each page checks that the signed-in user has the right role and an active profile. Sign-in needs the phone provider turned on in the Supabase project (decision D-001).

A new user has no profile until one is created with register_buyer or register_distributor, so after the first sign-in they see "no access" until registration exists.

## Checks

- `npm run typecheck --workspace @mitralink/web`
- `npx next build` in `apps/web`
