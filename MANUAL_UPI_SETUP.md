# Manual UPI QR payments (admin-verified)

This feature is **not** an automated payment gateway. It does not require a YouPI-PG merchant account. It uses your existing restaurant QR and an admin's bank reconciliation. It does **not** run or embed YouPI-PG; the upstream project's manual review principles informed the flow.

## Setup
1. Rotate any database password disclosed outside your secret manager. Never commit database passwords or service-role keys.
2. Back up the Supabase database. Apply the existing initial migration first if not already applied, then review and apply `supabase/migrations/202611150001_manual_upi.sql` exactly once through your controlled migration process.
3. Upload the restaurant's existing QR image to an HTTPS location you control (for example a public Supabase Storage object). Ensure the QR is your own, and test that its payee details match your bank account. Do not upload credentials.
4. Sign in as admin and set **UPI QR image HTTPS URL** in Settings. Leave it blank until the image is available; customers cannot submit a new claim from the UI without a configured QR.
5. Test with synthetic orders and bank-confirmed test transactions before accepting real orders.

## Payment states
- Customer selects **UPI QR · manual bank verification** and places an order. The database reserves stock and leaves order payment pending.
- In Orders, the customer views the configured QR and submits a 12–22 digit numeric UTR. This is a **claim**, not proof of payment.
- Admin sees the claim in Orders. **Only after independently confirming bank credit, payee, amount and reference**, admin enters an evidence note and approves. This atomically marks payment paid and order confirmed.
- Admin may reject with a reason. Rejected orders are not confirmed; handle stock restoration/reconciliation with a documented staff procedure. The rejection flow deliberately does not automatically release reserved stock.
- A claimed order cannot be cancelled by the existing cancellation RPC until manually reconciled.
- Kitchen progression remains blocked unless payment is confirmed.

## Limitations and security
- This implementation does not connect to the YouPI-PG server and does not automate QR settlement checks, payment gateway webhooks or bank reconciliation.
- No customer-entered UTR or QR scan is automatically treated as payment success.
- Existing Razorpay integration remains available separately.
- Admin authority is enforced in a PostgreSQL RPC using `my_role()`; customers may only claim their own orders.
- Never put the database connection string in frontend variables.
- This change has not yet been verified against your live Supabase project. Test migration, RLS, stock behavior, and UI end-to-end in staging before deploying.
