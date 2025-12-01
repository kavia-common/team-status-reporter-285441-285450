#!/usr/bin/env bash
set -euo pipefail

# Team Status Reporter - PostgreSQL Schema Initializer
# Usage:
#   cd team-status-reporter-285441-285450/postgres_database
#   ./init_schema.sh
#   ./init_schema.sh --seed
#
# Requires: db_connection.txt containing a psql connection command, e.g.:
#   psql postgresql://appuser:dbuser123@localhost:5000/myapp
#
# This script:
# - Validates presence of psql
# - Reads and normalizes the connection URL from db_connection.txt (trims leading 'psql ' and whitespace/CR)
# - Applies schema with psql "$URL" to avoid socket fallback issues
# - Optionally applies seed when --seed flag is used

log() { echo "[init_schema] $*"; }
fail() { echo "[init_schema][ERROR] $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Validate psql availability
if ! command -v psql >/dev/null 2>&1; then
  fail "psql command not found. Please install PostgreSQL client tools and retry."
fi

# Check required files
if [[ ! -f "./db_connection.txt" ]]; then
  fail "db_connection.txt not found in $(pwd)
Hint: Run startup.sh first to bootstrap DB and create db_connection.txt, or create it manually with:
  psql postgresql://appuser:dbuser123@localhost:5000/myapp"
fi

if [[ ! -f "./schema/init_schema.sql" ]]; then
  fail "Missing schema file: ./schema/init_schema.sql"
fi

# Normalize and read connection URL from db_connection.txt
# Strips leading 'psql ' if present, trims trailing spaces, and removes CR characters
CONN_URL="$(sed -E 's/^psql[ ]*//;s/[[:space:]]+$//' db_connection.txt | tr -d '\r')"

# Handle possible empty or malformed URL
if [[ -z "${CONN_URL}" ]]; then
  fail "Parsed connection URL is empty. Check contents of db_connection.txt"
fi

# Log the connection being used (without quotes to show the raw tokenization, but still safe)
log "Using connection: psql ${CONN_URL}"

# Apply schema
log "Applying schema from ./schema/init_schema.sql ..."
# Use explicit quoting to pass the full URL as a single argument to psql
psql "${CONN_URL}" -v ON_ERROR_STOP=1 -f "schema/init_schema.sql" || fail "Failed to apply schema."

# Optional seed
if [[ "${1-}" == "--seed" ]]; then
  if [[ ! -f "./schema/seed_dev.sql" ]]; then
    fail "Seed flag provided but seed file missing: ./schema/seed_dev.sql"
  fi
  log "Applying development seed data from ./schema/seed_dev.sql ..."
  psql "${CONN_URL}" -v ON_ERROR_STOP=1 -f "schema/seed_dev.sql" || fail "Failed to apply seed data."
fi

log "Done."
