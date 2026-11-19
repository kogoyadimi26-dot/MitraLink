# MitraLink mobile app

Expo (React Native), Android first. Used by buyers and agents, and later distributors. Scaffold only.

## Run locally

1. From the repository root: `npm install`
2. Copy `apps/mobile/.env.example` to `apps/mobile/.env` and fill in the dev project's URL and publishable key.
3. `npm run start --workspace @mitralink/mobile`, then open the project in Expo Go or an emulator.

## Screens (scaffold)

- Home: entry point to the catalogue and to the buyer's orders
- Catalogue: Jayapura products from the `browse_catalogue` function, with add to basket
- Basket: one group per distributor. Each group is sent with `place_order`, using a client id so a retry never creates a second order
- Orders: the signed-in user's orders (row-level security)
- Order detail: status, bank details from `get_payment_instructions` (only while payment is due or received), confirm receipt and report a problem, both through `transition_order`

Basket rules live in `lib/cart.ts` and have tests (`npm run test --workspace @mitralink/mobile`).

## Not built yet

- Sign-in (waits for D-001). Until then, basket sends and orders show a sign-in message.
- Working with a signed-in user: the screens call the database directly, so they work online only
- Offline queue and sync status (uses PowerSync, waits for the PowerSync project)
- Bahasa Indonesia strings (screens use placeholder text; the full set is in `strings/id.json`)

## Checks

- `npm run typecheck --workspace @mitralink/mobile`
- `npx expo export --platform android` in `apps/mobile` creates an Android bundle.
