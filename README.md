# Sabarish Fast Food · mobile web app

React + Vite, Supabase/PostgreSQL and Razorpay. An installable, responsive **web app (PWA)** for Android and iPhone; this repository does not contain a native APK or iOS binary.

## Current state

The application source and production build are ready for configuration. No Supabase project, live database, payment credentials or public deployment is bundled. Without configuration, the UI shows a setup notice and no fabricated products or sales.

Included:

- Mobile bottom navigation, menu search/categories, bag and checkout.
- Email registration, sign-in, sign-out and password recovery with Supabase Auth.
- Customer order history, payment retry and 15-second order refresh.
- Cashier cash billing and paid-order kitchen status progression.
- Admin product/price/stock editing, item deactivation, category creation, staff roles and restaurant settings.
- Paid-revenue overview and 7-day chart based on the latest 500 orders; this is explicitly labelled, not an all-time accounting report.
- Printable receipts; select **Save as PDF** in the browser print dialog.
- Stock reservations and totals calculated transactionally in PostgreSQL, RLS, inventory audit records and idempotent order/payment operations.
- Razorpay server order creation, checkout signature verification, captured-payment/amount verification and signed `payment.captured` webhook handling.
- PWA manifest, icons and a dedicated offline fallback. Ordering requires an internet connection; customer/API/payment data is never service-worker cached.

## 1. Run in VS Code

Install Node.js 22.12 or newer. Then:

```bash
git clone https://github.com/DSABARISH-D/sabfoods-tracker-0.02.git
cd sabfoods-tracker-0.02
npm ci
cp .env.example .env
npm run dev
```

On Windows PowerShell, use `Copy-Item .env.example .env` instead of `cp` if preferred.

Set these two values in `.env` and restart Vite:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

Only a publishable/anon key belongs in the frontend. Never put a service-role key or Razorpay secret into a `VITE_` variable, GitHub, or chat.

## 2. Database and authentication

1. Create a new Supabase project.
2. Run `supabase/migrations/202611130001_initial.sql` in its SQL editor **once**, on a fresh database. Alternatively link the Supabase CLI to the project and run `supabase db push`.
3. Enable email/password authentication. Set the Auth Site URL and allowed redirect URLs to your deployed app URL (and `http://localhost:5173/` for local development).
4. Register your own account and confirm the email.
5. In the SQL editor, promote your verified account using its exact email:

```sql
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = 'YOUR_OWN_EMAIL');
```

6. Sign out and back in. Open **Products & inventory** and set actual available stock. Seeded stock deliberately starts at zero. The supplied menu prices are seeded in the database, never hardcoded into the frontend.
7. Set your restaurant contact details and hours under Settings. Staff register first; the admin assigns cashier roles under Team.

`products.stock_quantity` is the single stock source; `inventory_history` records changes. There is no second stock balance that can drift from it. Deactivate used products instead of deleting them; foreign keys preserve historic order references. Each Chicken Chilli unit means one 100g portion.

## 3. Razorpay test setup

Use a Razorpay **test** account first. Configure automatic capture. Set these server-only secrets through Supabase Edge Function settings (or the Supabase CLI):

- `RAZORPAY_KEY_ID`
- `RAZORPAY_KEY_SECRET`
- `RAZORPAY_WEBHOOK_SECRET` (your chosen webhook signing secret)

Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` inside hosted functions. Deploy:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy create-payment
supabase functions deploy verify-payment
supabase functions deploy razorpay-webhook
```

The committed `supabase/config.toml` disables the gateway's legacy JWT check. The two user functions explicitly validate the bearer token with `auth.getUser()` and verify order ownership. The webhook instead verifies the HMAC of the **raw body**. Do not remove these application-level checks.

Configure a Razorpay webhook for `payment.captured` at:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/razorpay-webhook
```

Use the same signing secret configured in Supabase. Payment is only marked paid after capture, INR currency, expected order and exact amount have been verified. Closing checkout or a failed attempt leaves the order pending and allows retry; it does not falsely mark payment successful. Repeated verified callbacks/webhooks are idempotent.

Online orders reserve stock immediately. Staff may cancel an unpaid order before a Razorpay order is attached, restoring stock once. After payment initiation, automatic cancellation is deliberately blocked to avoid a late captured payment racing released stock. Reconcile abandoned payments with Razorpay before manually resolving them. Automated reservation expiry, refunds, failed-attempt audit history and reconciliation tooling remain future work.

## 4. Build and deploy

```bash
npm test
npm run build
npm run preview
```

Import this GitHub repository into Vercel or Netlify:

- Build: `npm run build`
- Output: `dist`
- Node: 22.12 or newer
- Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the hosting environment, then rebuild.
- Add the resulting HTTPS URL to Supabase Auth's allowed redirects.

`vercel.json` and `netlify.toml` are included. GitHub stores the code; pushing alone does not publish a working site or configure the database.

## 5. Use on a phone

Open the deployed **HTTPS** URL:

- Android: Chrome menu → **Add to Home screen / Install app** (wording depends on browser).
- iPhone: Safari Share → **Add to Home Screen**.

The app then launches from its own home-screen icon. PWA installation depends on browser support. Native store packaging is not included.

For a temporary layout check, run `npm run dev` on your laptop and open Vite's Network URL on a phone on the same Wi-Fi. Allow the development port through the laptop firewall if necessary. Plain LAN HTTP may not support secure-context features such as PWA installation and `crypto.randomUUID`; use the deployed HTTPS URL for checkout and installation testing.

## Verification and remaining release work

Locally verified:

- `npm run build` succeeds.
- Cart arithmetic and stock quantity limits pass Node tests.
- The complete migration runs in PGlite (embedded PostgreSQL).
- Database tests check cash permissions, self-promotion prevention, customer price-edit denial, private order/item access, insufficient-stock rollback, order retry idempotency, service-only payment confirmation, amount mismatch rejection, repeated confirmation, paid-order advancement and cancellation stock restoration.
- Desktop and 390px mobile setup/empty states visually checked in a browser.

Not yet verified: real Supabase authentication/email delivery, hosted RLS integration, actual simultaneous stock transactions, deployed Edge Functions, Razorpay success/failure/cancelled payment flows, real webhook delivery, physical-device install and receipt printing. Complete these in test mode before accepting real restaurant orders.

Not yet implemented from the wider restaurant-management specification: authorized discounts, full paginated financial reports/monthly breakdowns/best-seller analysis, standalone transaction/inventory-history screens, automatic refunds, reservation expiry and native app-store builds. The current app is a configured-and-tested-first release foundation, not a claim of production certification.

Official references:

- https://supabase.com/docs/reference/javascript/auth-getuser
- https://supabase.com/docs/guides/functions/auth
- https://razorpay.com/docs/payments/payment-gateway/web-integration/standard/integration-steps/
