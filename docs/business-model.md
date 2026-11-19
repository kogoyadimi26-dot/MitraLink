# Business model

## Who pays

| Party | Pays for | Amount |
|---|---|---|
| Buyer | Nothing. Joining is always free. | Rp0 |
| Distributor | Commission on each confirmed sale | Per-category rate, with a Rp25,000 minimum per order |
| Distributor (optional, later) | Monthly listing or verified badge | Not in the test |

The buyer pays the distributor the full basket directly during the test. The distributor pays our commission invoice by bank transfer.

## Commission rates (placeholders to test)

| Category | Rate | Basket where the % beats the minimum |
|---|---|---|
| Staples | 1.5% | Rp1,666,667 |
| School and office supplies | 3% | Rp833,333 |
| Household goods | 3% | Rp833,333 |
| Electronics and tools | 2% | Rp1,250,000 |
| Restricted goods | Not allowed | — |

Below these basket sizes the Rp25,000 minimum applies. Example: a Rp100,000 order pays Rp25,000, which is 25% of the basket.

**Commission is per order, not per item.** An order with many items earns one commission, based on the order's total value.

## Unit economics per order

| Item | Amount (IDR) |
|---|---|
| Commission (minimum) | 25,000 |
| WhatsApp messages (about 3 per order, at Rp586 each, the high end) | 1,760 |
| Agent fee (proposed, Option B: Rp5,000 per confirmed order) | 5,000 |
| **Contribution per order (with agent fee)** | **18,240** |
| Contribution per order (without agent fee) | 23,240 |

## Monthly fixed costs (launch estimate)

| Item | USD | IDR (at Rp16,000/USD) |
|---|---|---|
| Supabase Pro (database, login, storage) | 25 | 400,000 |
| Vercel Pro (dashboard hosting, 1 seat) | 20 | 320,000 |
| PowerSync (free tier) | 0 | 0 |
| Expo (free tier) | 0 | 0 |
| Domain (Rp300,000 a year) | — | 25,000 |
| **Total fixed** | **45** | **745,000** |

Other costs:

- WhatsApp: about Rp1,760 per order (see unit economics).
- Email for invoices: an estimate of $7 per seat, not checked.
- Card fees, VAT on foreign services, bank transfer fees and accounting are not included.

Prices are from third-party sources. Check each vendor's official pricing page before budgeting.

## One-time costs (CapEx)

| Item | IDR |
|---|---|
| Google Play developer account ($25) | 400,000 |
| Two low-end Android test phones (estimate) | 2,000,000 |
| Domain, first year (estimate) | 300,000 |
| Contingency (10%) | 270,000 |
| **Total (managed cloud)** | **≈ 2,970,000** |

A development laptop adds about Rp10,000,000 if you don't already have one. Outsourced development is excluded.

## Break-even

**Without agent fee:** 745,000 ÷ 23,240 ≈ **33 orders a month**

**With Rp5,000 agent fee per order:** 745,000 ÷ 18,240 ≈ **41 orders a month**

## Net profit by volume (with Rp5,000 agent fee)

Revenue uses only the minimum commission. Percentage commission on larger baskets is extra. Figures are before tax.

| Orders per month | Revenue | Fixed costs | WhatsApp | Agent fees | Net profit |
|---|---|---|---|---|---|
| 20 | 500,000 | 745,000 | 35,200 | 100,000 | −380,200 |
| 41 | 1,025,000 | 745,000 | 72,160 | 205,000 | ≈ 2,840 (break-even) |
| 100 | 2,500,000 | 745,000 | 176,000 | 500,000 | 1,079,000 |
| 200 | 5,000,000 | 745,000 | 352,000 | 1,000,000 | 2,903,000 |

## Payback

One-time CapEx of about Rp2.97 million (with the Rp5,000 agent fee):

- At 100 orders a month: about 3 months.
- At 60 orders a month: about 9 months.
- At break-even (41 orders a month): it never pays back.

## Tax

Small businesses in Indonesia may pay a final tax of about 0.5% of turnover under PP 55/2022. Confirm with a tax adviser. Agent payments may need withholding tax.

## Payment model

- **Test (Option A):** direct bank transfer from buyer to distributor. We never hold money. Confirm payment from the bank statement.
- **App (Option B):** a licensed payment gateway with split payouts (for example Midtrans, Xendit or DOKU). Gateway fees reduce the contribution per order. Check the fee on expected order sizes and redo the break-even. Confirm the legal model with a lawyer first.
- **Avoid (Option C):** the platform collecting buyer money into its own account without a Bank Indonesia payment licence.
