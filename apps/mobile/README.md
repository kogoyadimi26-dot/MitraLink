# MitraLink mobile app

Expo (React Native), Android first. Used by buyers and agents, and later distributors. Scaffold only.

## Run locally

1. From the repository root: `npm install`
2. Copy `apps/mobile/.env.example` to `apps/mobile/.env` and fill in the dev project's URL and publishable key.
3. `npm run start --workspace @mitralink/mobile`, then open the project in Expo Go or an emulator.

## Sign-in

The app asks for a phone number, sends a one-time code by SMS, and keeps the session on the device (AsyncStorage). It needs the phone provider turned on in the Supabase project first (see below).

## Screens

- Home: entry point to the catalogue and to the buyer's orders
- Catalogue: Jayapura products from the `browse_catalogue` function, with add to basket
- Basket: one group per distributor. Each group is sent with `place_order`, using a client id so a retry never creates a second order
- Orders: the signed-in user's orders (row-level security)
- Order detail: status, bank details from `get_payment_instructions` (only while payment is due or received), confirm receipt and report a problem, both through `transition_order`

Basket rules live in `lib/cart.ts` and have tests (`npm run test --workspace @mitralink/mobile`).

## Supabase setup for sign-in (needs the founder's decision, D-001)

In the Supabase dashboard, under Authentication, turn on the Phone provider, choose the SMS provider, and enter that provider's credentials. Until this is done, sending a code shows the provider error.

## Not built yet

- Registration after the first sign-in (a new user has no profile until one is created with register_buyer)

- Working with a signed-in user: the screens call the database directly, so they work online only
- Offline queue and sync status (uses PowerSync, waits for the PowerSync project)
- Bahasa Indonesia strings (screens use placeholder text; the full set is in `strings/id.json`)

## Checks

- `npm run typecheck --workspace @mitralink/mobile`
- `npx expo export --platform android` in `apps/mobile` creates an Android bundle.
