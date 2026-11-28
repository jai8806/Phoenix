# Operations: keeping Phoenix up and backed up (free plan)

Phoenix runs on Supabase's free plan. Two GitHub Actions cover its gaps:

| Gap on the free plan | Workflow | Schedule |
|---|---|---|
| The project pauses after a week with no activity | `supabase-keepalive.yml` reads one row | every 3 days |
| No automatic backups | `supabase-backup.yml` dumps the database to Google Cloud Storage | Sundays, 02:13 IST |

Scheduled workflows only run from the repository's **default branch**, so
they start once this branch is merged.

## One-time setup

### 1. A Cloud Storage bucket (Google Cloud console → Cloud Storage → Create)

- **Name:** anything unique, e.g. `phoenix-ncc-rvce-backups`.
- **Location:** Region, **us-central1** (or us-east1 / us-west1). These regions
  are in Google's Always Free tier (5 GB). Backups are a few MB each.
- **Storage class:** Standard. **Access:** uniform, public access prevention on.
- **Lifecycle** (bucket → Lifecycle → Add rule): *Delete object* when *age* is
  **120 days**. That keeps about 17 weekly backups.

### 2. A service account that can only write to that bucket

1. IAM & Admin → Service accounts → Create: name `phoenix-backup`. Skip the
   project-wide roles.
2. Open the bucket → Permissions → Grant access → the service account's email →
   roles **Storage Object Creator** and **Storage Object Viewer**.
3. Service account → Keys → Add key → JSON. A file downloads; it goes into
   GitHub in step 4 and nowhere else. If key creation is blocked by an
   organisation policy, use a personal Google Cloud project.

### 3. The database connection string (Supabase dashboard)

**Connect** (top bar) → **Session pooler** → copy the URI. Replace
`[YOUR-PASSWORD]` with the database password (Project Settings → Database →
Reset database password if you don't have it). Use the session pooler: GitHub's
runners can't reach the direct connection, which is IPv6 only.

### 4. GitHub (repository → Settings → Secrets and variables → Actions)

| Kind | Name | Value |
|---|---|---|
| Secret | `SUPABASE_DB_URL` | the URI from step 3 |
| Secret | `GCP_SA_KEY` | the whole JSON file from step 2 |
| Variable | `GCS_BACKUP_BUCKET` | the bucket name, e.g. `phoenix-ncc-rvce-backups` |
| Variable | `SUPABASE_URL` | `https://<project>.supabase.co` |
| Variable | `SUPABASE_PUBLISHABLE_KEY` | the publishable key the app uses |

Then Actions → each workflow → **Run workflow** once to check it.

## Restoring

Download a backup (Cloud Storage → bucket → `phoenix/` → file → Download), then
restore into a fresh Supabase project, or into the same one after a bad change:

```bash
pg_restore --no-owner --clean --if-exists --schema=public -d "$SUPABASE_DB_URL" phoenix-2026-11-29T2043Z.dump
```

`--schema=public` restores the app's tables only. Add `--schema=auth` to bring
back accounts as well (only into a fresh project). To restore one table, add
`--table=diary_entries`. An error that `schema "public" already exists` is
harmless.

What the backup doesn't hold: figure images in Storage and the précis load
scripts. Both are rebuilt from the files in `content/build/`
(`precis-figures*.zip`, `supabase_setup/`), so keep a copy of that folder.

## If the project paused anyway

Supabase dashboard → the project → **Restore project**. Paused free projects
can be restored for 90 days. Then check that the keep-alive workflow is
running (Actions tab).
