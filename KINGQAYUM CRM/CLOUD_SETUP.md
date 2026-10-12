# Cloud upgrade and deployment status

## Release status

This checkout is an offline, single-browser IndexedDB CRM. The Supabase SQL migration and `workspace-admin` Edge Function are preparatory artifacts only. The frontend does not yet authenticate, read or write cloud records, enforce a signed-in workspace, queue edits, resolve conflicts, or migrate local records to Supabase. Do not use the current site for shared business data or treat a local edit as a cloud edit. The supplied SQL has not been run against a Supabase project.

This distinction is intentional: importing business data before the client-side migration has been exercised against a disposable project would put records at risk. Existing IndexedDB records are not automatically deleted or uploaded.

## Configuration values

The eventual browser build needs only these public values, set as Vercel **Production, Preview, and Development** environment variables:

- `SUPABASE_URL`: project URL, such as `https://<project-ref>.supabase.co`.
- `SUPABASE_PUBLISHABLE_KEY`: the project's publishable key (legacy projects may label this `anon`). This key is public and safe to ship only with correctly configured RLS.
- `SUPABASE_WORKSPACE_ID`: the workspace UUID created by the trusted first-owner setup.

No privileged secret belongs in browser variables, frontend source, Git, or public build output. The Edge Function requires `SUPABASE_SERVICE_ROLE_KEY` as a Supabase Function secret, plus `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `APP_ORIGIN`. Never send secrets in chat.

These variables are not consumed by the current frontend; configuring them alone does not enable cloud features.

## Phase 1 database review and isolated test procedure

The migration creates workspace-scoped composite primary/foreign keys, RLS on all ten tables, member-only record policies, a separate owner/admin settings-write policy, and no browser membership-write grants. The policy helper functions and payment RPC use `SECURITY DEFINER` with an empty `search_path` and schema-qualified objects. `record_payment` checks membership, serializes a payment idempotency key, returns only an exact retry, locks the order row before checking its remaining balance, and inserts the payment in the same database transaction. Record IDs and workspace IDs are immutable after insert through the record triggers. The service-role key is used only by the trusted Edge Function.

Migrations are applied once by Supabase's migration history; do not paste the migration into SQL Editor repeatedly. `supabase db reset --local` is intentionally destructive to the **local Docker database only**: it recreates that disposable DB and replays migrations from an empty state. Do not use `db reset --linked` for this rehearsal.

Required local tools: current Supabase CLI with `supabase test db` support, Docker Desktop or another Docker-compatible runtime, and enough memory for the local Supabase stack (Supabase currently recommends 7 GB RAM). Python is only needed for this repo's source-level tests. Supabase uses pgTAP for its database test command.

From the repository root, run:

```sh
supabase --version
supabase start
supabase db reset --local
supabase test db --local
```

The reset applies `supabase/migrations/202610110001_shared_workspace.sql`; the test runner executes `supabase/tests/database_security.test.sql`. That pgTAP file creates four isolated Auth user rows in its test transaction, uses the `authenticated` database role with different JWT subject claims for an owner, a workspace member, another workspace owner, and a non-member, and rolls its fixtures back. It checks member reads and edits, non-member visibility and mutations for workspace-owned records, settings permissions, payment RPC denial, exact payment retries, mismatched retry rejection, and over-balance rejection. The test's results are the required evidence; the Python source checks alone do not establish database security.

For a disposable hosted Supabase project instead of local Docker:

1. Create a new throwaway project with no business data. Keep its database password private; `supabase link` can prompt for it. The CLI access token and DB password must not be committed or pasted into this repository.
2. From this repository, run `supabase login` and `supabase link --project-ref YOUR_DISPOSABLE_PROJECT_REF`.
3. Confirm the linked project is the throwaway one with `supabase projects list`, then apply the pending migration with `supabase db push --linked`.
4. Run `supabase test db --linked`. The tests use transaction-scoped fixtures and roll them back. Remove the throwaway project from the Supabase Dashboard after review.

Do not run `supabase db reset --linked` for this procedure: that command drops the linked database schema and data. A hosted run is not a substitute for reviewing the target project ref before migration.

If a local or linked run fails, capture the failing pgTAP assertion and SQL error, fix the migration/test, then reset only the local database and rerun. Do not mark Phase 1 security verified from static inspection; only report the database suite as passed after `supabase test db` completes successfully against the intended disposable database.

For additional manual SQL Editor checks, create two disposable confirmed users in Auth, bootstrap a workspace for User A with the trusted owner procedure below, and invite User B into that workspace. Sign in as each user through the Data API and verify User A and invited User B can read the workspace rows while a third signed-in user receives empty SELECT results and zero affected rows on UPDATE/DELETE; an INSERT violating RLS should return `42501`. Also verify User A can edit workspace settings while User B cannot. The pgTAP suite automates the central member/non-member checks and should be run first.

## First-owner setup (when the client release is ready)

1. Create a Supabase project. Disable public sign-ups; configure email delivery and Auth URL allow-list entries for the exact production and preview origins you intend to use.
2. Apply `supabase/migrations/202610110001_shared_workspace.sql` to a disposable project first. Exercise RLS as a member and a non-member, plus payment RPC behavior. Only then apply the reviewed migration to production.
3. In Supabase Auth, invite the first owner using the dashboard's trusted **Invite user** flow. Have them accept and confirm their email.
4. Run this bootstrap once in the SQL editor, substituting the confirmed owner's email. Record the returned workspace ID using the SQL editor's results (or query `select id, name from public.workspaces`). Do not rerun blindly: each run creates a new workspace.

```sql
do $$
declare owner_id uuid; workspace_id uuid;
begin
  select id into strict owner_id from auth.users
   where lower(email) = lower('OWNER_EMAIL_HERE') and email_confirmed_at is not null;
  insert into public.workspaces(name, owner_user_id)
   values ('KingQayumEditz', owner_id) returning id into workspace_id;
  insert into public.workspace_memberships(workspace_id, user_id, role)
   values (workspace_id, owner_id, 'owner');
  insert into public.workspace_settings(workspace_id) values (workspace_id);
  raise notice 'Workspace ID: %', workspace_id;
end $$;
```

## Team invitations

When deployed, link and deploy the trusted function:

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set APP_ORIGIN=https://YOUR_VERCEL_HOST
supabase secrets set SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
supabase secrets set SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_SECRET
supabase functions deploy workspace-admin
```

An owner/admin invitation screen still needs to be implemented in the frontend. Until then, use only the Supabase dashboard's trusted Auth invitation flow and do not manually grant memberships to unverified addresses. Never call Auth Admin APIs from browser code.

## Vercel static hosting

The repository includes `vercel.json` headers for the service worker. Import the Git repository into Vercel and deploy the project root as a static site with no framework build command and no output directory. Add the three public configuration variables above only when the cloud client exists. Configure the Vercel production URL and any chosen preview URLs in Supabase **Authentication → URL Configuration** (Site URL and Redirect URLs); use exact HTTPS origins and a callback path supported by the final auth client. The current local-only frontend has no sign-in callback.

## Offline behavior

The current app caches its shell and uses IndexedDB, so previously stored local data and app assets remain usable offline after the first successful load. Local records and settings can be edited offline. WhatsApp links, clipboard access, and any future hosted authentication/cloud sync require connectivity. There is currently no sync queue and no cloud state to which edits could be reported. Keep backups on a separate device or storage service.

The service worker uses a versioned cache, installs a new cache completely before activation, prefers fresh same-origin assets online, and retains cached files for offline fallback. After deployment, close old app tabs and reopen if an old tab remains on a previous app version.

## Safe migration and backup/restore procedure

Cloud import is not implemented yet. For a future release, use this required rehearsal before importing real business data:

1. From **Settings → Export JSON backup**, save a dated backup. Preserve the original file unchanged and make a second working copy.
2. Restore the working copy into a separate browser profile or disposable environment. Validate record counts and relationships there.
3. Import that copy into a disposable Supabase project using preview-first, insert-only/idempotent migration semantics. Any existing cloud ID collision must be reported and skipped or rejected; never overwrite silently.
4. Compare per-store imported/skipped/failed counts, prospect histories, order balances, and payment totals. Retry the same import and confirm it adds no duplicate interactions or payments.
5. Verify records from two authorized sessions and an unauthorized session. Only after review should the same process be considered for production.
6. Retain the original IndexedDB records and backup until cloud counts, relationships, and payment totals have been checked and a fresh cloud backup has been restored successfully in a separate workspace.

For current local recovery, export JSON regularly. To restore, use **Settings → Choose backup**, review validation, then explicitly select merge or replace. Merge remaps colliding local IDs and references; replace is destructive to that browser's current data. Keep a separate copy before using replace. A cloud backup/export and cloud restore path do not exist yet.

## Required remaining implementation and verification

Before calling this a cloud release, implement the frontend auth gate, membership lookup, workspace-scoped data access, transactional migration RPC with import report, serialized offline mutation queue, revision-based conflict UI, idempotent payment RPC integration, and cloud backup/restore. Then execute the acceptance matrix in `README.md` on a disposable project. This workspace has no configured Supabase credentials or second authenticated browser session, so those integration checks cannot be claimed as passed.
