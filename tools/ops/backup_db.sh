#!/usr/bin/env bash
# Dump the Phoenix database to a compressed file.
#
#   SUPABASE_DB_URL=postgresql://... tools/ops/backup_db.sh out_dir
#
# Dumps the app's data (public), accounts (auth) and file metadata (storage)
# in pg_dump's custom format, so single tables can be restored on their own.
# Prints the path of the file it wrote.
set -euo pipefail

: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL to the database connection string}"
out_dir="${1:-.}"
mkdir -p "$out_dir"
stamp="$(date -u +%Y-%m-%dT%H%MZ)"
file="$out_dir/phoenix-$stamp.dump"

pg_dump "$SUPABASE_DB_URL" \
  --format=custom --compress=9 \
  --schema=public --schema=auth --schema=storage \
  --no-owner --no-privileges \
  --file="$file"

# A dump that lists no tables means something went wrong.
tables="$(pg_restore --list "$file" | grep -c ' TABLE DATA ' || true)"
if [ "$tables" -lt 5 ]; then
  echo "Backup looks empty ($tables tables); not keeping it." >&2
  rm -f "$file"
  exit 1
fi
echo "$file"
