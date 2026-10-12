# KingQayum CRM

Offline-first prospect, follow-up, client, project, and payment tracker for KingQayumEditz. The running frontend in this checkout stores records in this browser's IndexedDB only. Supabase schema and workspace administration scaffolding are present, but cloud authentication, shared data access, synchronization, and migration are not implemented. Do not use it as a shared cloud CRM yet.

## Run locally

Install Python 3 and run `python launch.py` (Windows: `py launch.py`). Open the localhost URL shown by the launcher. Use localhost or HTTPS for reliable service worker installation; `file://` does not support reliable install/offline behavior.

## Offline and install

Load once while connected. The service worker caches the app shell; previously saved IndexedDB records remain available offline in that same browser profile. Local CRM edits work offline. Hosted sign-in, cloud sync, WhatsApp links, and clipboard features require connectivity or browser permission; no cloud sync is currently implemented, so local changes never claim to have reached a server. Install from the browser menu where supported.

The worker uses versioned caches and network-first same-origin asset refresh with cached fallback. Deployments should bump the cache name in `sw.js` when changing the app shell. If an old tab stays open through an upgrade, close and reopen the app.

## DM Studio

Open **DM Studio** from the sidebar to prepare a cold outreach message, follow-up, or reply. Select a saved prospect to use its business name, category, service, observed opportunity, interaction history, status, and follow-up schedule, or enter temporary details that stay only in the form. Choose a service, context, tone, and length, then generate an editable draft.

DM Studio works offline using transparent template/rule-based generation, including variations for graphic design, flyers, branding, social media designs, photo editing, and web design. It does not invent research, prices, timelines, samples, sales results, or prior conversations. When information is missing it uses neutral language or asks for the needed scope. It blocks new follow-up suggestions and interaction records for prospects marked **Rejected** or **Not interested**.

Copying, generating, and saving a draft as a template do not mark a prospect contacted or create history. Use **Record real contact** only after you actually use the message; the app asks for confirmation and then creates the appropriate interaction. Drafts for temporary prospects cannot be recorded. Saved drafts appear in **Message library** as `DM Studio` templates and can be edited there.

### Optional online AI

This checkout deliberately has no live online provider configured. Selecting Online displays an unavailable state and produces an offline draft; no prospect data is sent anywhere. `js/dm-studio.js` includes a provider adapter contract for a future trusted server-side proxy. Do not put provider API keys in frontend code, IndexedDB, localStorage, `.env` files committed to Git, or Vercel public variables.

To enable a provider in a future backend release, create an authenticated server or Edge Function endpoint that accepts only the selected fields needed for a single request, validates them, applies rate limits and access control, holds the secret server-side, and returns `{ "text": "..." }`. Wire that endpoint to the adapter only after an end-to-end security review. Handle timeout, `429`, malformed responses, and network errors by showing an error and retaining the offline fallback. The current local-only application has no authentication, so exposing an AI endpoint now would be unsafe.

## Backups and local data

Use **Settings → Export JSON backup** regularly and keep copies outside the browser profile. Restore supports merge and explicit replace; merge remaps colliding IDs and linked references, while replace clears current local records. Validate a backup in a separate browser profile before any destructive restore. The app does not encrypt IndexedDB data.

## Cloud upgrade and Vercel

See [CLOUD_SETUP.md](CLOUD_SETUP.md) for first-owner setup, invitation endpoint secrets, Vercel static hosting, public configuration values, and the required migration rehearsal. The SQL migration has not been applied to a live project. The current frontend does not consume Supabase configuration, authenticate, synchronize, or import to the cloud. Do not put service-role keys or other privileged credentials in frontend code or Vercel public variables.

## Verification

Run source-level project checks with `python -m unittest discover -s tests -v`. They validate static wiring and safety contracts only; they do not run a browser, Supabase, authentication, offline sync, or cross-device tests. For the eventual cloud release, verify sign-in/out, unauthorized denial, workspace membership, two-session reads/edits, phone/computer sync, offline queue replay, conflict resolution, import counts/idempotency, payment math, backup/restore, service-worker update, and Vercel redirects using a disposable Supabase project. No such cloud test has been executed from this workspace.
