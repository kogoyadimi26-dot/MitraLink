# MitraLink web dashboard

Next.js (App Router, TypeScript). Used by distributors and the admin team. Scaffold only.

## Run locally

1. From the repository root: `npm install`
2. Copy `apps/web/.env.example` to `apps/web/.env.local` and fill in the dev project's URL and publishable key.
3. `npm run dev --workspace @mitralink/web`, then open http://localhost:3000

## Pages (scaffold)

- `/`: home, with links to the admin pages
- `/admin/kpi`: KPI report from the `kpi_report` function (admin)
- `/admin/approvals`: distributors waiting for approval (admin)

Sign-in is not built yet. Phone sign-in waits for the SMS provider decision (D-001), so these pages show data only for a signed-in admin once sign-in exists.

## Checks

- `npm run typecheck --workspace @mitralink/web`
- `npx next build` in `apps/web`
