# MitraLink mobile app

Expo (React Native), Android first. Used by buyers and agents, and later distributors. Scaffold only.

## Run locally

1. From the repository root: `npm install`
2. Copy `apps/mobile/.env.example` to `apps/mobile/.env` and fill in the dev project's URL and publishable key.
3. `npm run start --workspace @mitralink/mobile`, then open the project in Expo Go or an emulator.

## Screens (scaffold)

- Home: entry point with a button to the catalogue
- Catalogue: Jayapura products from the `browse_catalogue` function

## Not built yet

- Sign-in (waits for D-001)
- Basket, order status and receipt confirmation
- Offline queue and sync status (uses PowerSync, waits for the PowerSync project)
- Bahasa Indonesia strings (screens use placeholder text; the full set is in `strings/id.json`)

## Checks

- `npm run typecheck --workspace @mitralink/mobile`
- `npx expo export --platform android` in `apps/mobile` creates an Android bundle.
