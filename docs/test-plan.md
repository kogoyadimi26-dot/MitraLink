# Four-week test plan

**Goal:** test whether distributors will pay commission, and whether buyers will order, before building the app.

**Method:** a spreadsheet, WhatsApp and direct bank transfer. No app.

## Weekly plan

| Week | Goal |
|---|---|
| 1 | Sign 3 to 5 distributors in Jayapura and Wamena, with commission agreed in writing. Test the Rp25,000 minimum. Recruit and brief agents. |
| 1–2 | Register 30 buyers through agents. |
| 2–3 | Run orders through the form and WhatsApp. Track each order in the spreadsheet. Invoice commission weekly. |
| 4 | Review results and decide: build the app, change the model, or stop. |

## Success targets

- [ ] 3 of 5 distributors agree to commission
- [ ] 10 of 30 buyers place an order
- [ ] 10 or more orders a week
- [ ] 80% of orders confirmed on time (define the window before week 1, for example 3 days after shipping)
- [ ] 100% of commission invoices paid

## Week 4 decision rules (suggested)

- **Build the app:** all success targets are met.
- **Change the model:** distributors sign but buyers don't order, or the minimum fee is rejected.
- **Stop:** fewer than 3 distributors agree to commission.

## Order flow (WhatsApp)

1. Buyer asks an agent for goods. The agent checks the distributor catalogue and quotes the price.
2. Agent creates an order code (for example `PDC-W-0001`, W for Wamena, J for Jayapura) and adds a row to the sheet.
3. Agent sends the order to the distributor using a fixed template:

   ```
   Order PDC-W-0001
   Buyer: Kios Maju Jaya (Wamena)
   Items: 10 sacks rice, 5 cartons oil, 20 packs noodles
   Total: Rp1,000,000
   Please reply ACCEPT, then SHIP when sent.
   ```

4. Distributor replies ACCEPT, ships, and replies SHIP with the date.
5. Buyer pays the distributor by bank transfer, with the order code in the transfer reference. The distributor replies PAID after checking the bank.
6. Buyer replies RECEIVED to the agent. The agent marks the order confirmed.

Only orders in **Confirmed** status count toward targets.

## Tracking sheet

Use one spreadsheet with three tabs.

**Orders** (one row per order)

| Column | Example |
|---|---|
| Order ID | PDC-W-0001 |
| Date | 2 Dec 2026 |
| Buyer | Kios Maju Jaya |
| Town | Wamena |
| Agent | Agent A |
| Distributor | CV Papua Sejahtera |
| Basket (Rp) | 1,000,000 |
| Rate | 1.5% |
| Commission due (Rp) | `=MAX(G2*H2, 25000)` |
| Buyer paid (date) | |
| Shipped (date) | |
| Confirmed (date) | |
| Status | Ordered / Paid / Shipped / Confirmed / Disputed |
| Invoice no. | INV-0001 |
| Commission paid (date) | |

For a mixed basket, use the higher rate, or split the order into one row per category.

**Buyers:** name, town, agent, date registered, number of orders.

**Distributors:** name, town, commission agreed in writing (yes/no), date signed.

## Status rules

- **Ordered:** the distributor has accepted the order.
- **Paid:** the bank statement shows the transfer with the order code.
- **Shipped:** the distributor has sent the goods.
- **Confirmed:** the buyer has replied RECEIVED.
- **Disputed:** the buyer reports a problem.

## Weekly routine (about 30 minutes)

1. **Match payments:** check the bank statement against order codes. Mark matches as Paid.
2. **Check shipments:** any order paid more than 2 days ago with no ship date needs a follow-up.
3. **Close confirmed orders:** mark RECEIVED orders as Confirmed.
4. **Invoice:** send each distributor one invoice a week for confirmed orders, listing order IDs and commission.
5. **Chase unpaid invoices:** block new orders for any distributor with an invoice overdue more than 7 days.

## Agent payment (proposed)

- Option B: Rp5,000 per confirmed order.
- Pay only on confirmed orders, never on registrations.
- Pay monthly by bank transfer, after the distributor's commission has cleared.
- Agent terms in writing, signed by each agent.
- Confirm with a tax adviser whether withholding tax applies.

## Limits

- A WhatsApp message is not proof of payment. Only the bank statement is.
- Messages can be missed. Agents should check the sheet daily.
- Buyer personal details stay private. Restrict access to the sheet.
- The WhatsApp Business app is enough for a small test. Check current Meta terms before using it for more.

## Open questions before week 1

- Typical kios order size, which decides whether the minimum or the percentage applies.
- Whether distributors accept the Rp25,000 minimum.
- Confirmation window for "on time" (for example 3 days after shipping).
- Final agent fee amount.
