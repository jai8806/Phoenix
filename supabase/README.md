# Supabase

`migrations/` holds the schema. Apply it with the Supabase CLI
(`supabase db push`) or paste it into the SQL editor of a new project.

## Checking the row-level security rules

`tests/` runs the migration against a plain Postgres 16 with pgvector,
stubbing the parts of Supabase's `auth` schema it uses, then plays through a
cadet, a senior cadet, the ANO and a cadet from another unit. Each step prints
what to expect next to the real result.

```bash
createdb phoenix_check
psql -d phoenix_check -v ON_ERROR_STOP=1 -f tests/00_auth_stub.sql -f migrations/20261126000000_init.sql
psql -d phoenix_check -f tests/rls_check.sql
```

Some steps are meant to fail (for example a cadet trying to post an
announcement or promote themselves); the expected error is noted above each one.
