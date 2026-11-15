# Manual UPI QR payments (admin-verified)

This feature is **not** an automated payment gateway. It does not require a YouPI-PG merchant account. It uses your existing restaurant QR and an admin's bank reconciliation. It does **not** run or embed YouPI-PG; the upstream project's manual review principles informed the flow.

## Setup
1. Rotate any database password disclosed outside your secret manager. Never commit database passwords or service-role keys.
2. Back up the Supabase database. Apply the existing initial migration first if not already applied, then review and apply `supabase/migrations/202611150001_manual_upi.sql` exactly once through your controlled migration process.
3. Upload the restaurant's existing QR image as `restaurant-qr.png` into the **private** Supabase Storage bucket `staff-upi` (created by migration). Only authenticated admin/cashier roles can read it via a short-lived signed URL. Never use a public bucket or commit the QR image. Verify the payee before using it.
4. The QR is not available in customer screens. Staff can click **View staff-only QR** on a pending UPI order. The signed link expires after 60 seconds; do not distribute it publicly. Customers must pay in person with staff assistance, then enter the UTR.
5. Test with synthetic orders and bank-confirmed test transactions before accepting real orders.

## Payment states
- Customer selects **UPI QR · manual bank verification** and places an order. The database reserves stock and leaves order payment pending.
- Staff privately shows the QR in person; in Orders, the customer submits a 12–22 digit numeric UTR. This is a **claim**, not proof of payment.
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
