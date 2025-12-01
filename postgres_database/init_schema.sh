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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "./db_connection.txt" ]]; then
  echo "ERROR: db_connection.txt not found in $(pwd)"
  echo "Hint: Run startup.sh first to bootstrap DB and create db_connection.txt, or create it manually with:"
  echo "  psql postgresql://appuser:dbuser123@localhost:5000/myapp"
  exit 1
fi

CONN="$(tail -n 1 ./db_connection.txt)"

echo "[init_schema] Using connection: ${CONN}"
echo "[init_schema] Applying schema..."
psql "$CONN" -v ON_ERROR_STOP=1 -f ./schema/init_schema.sql

if [[ "${1-}" == "--seed" ]]; then
  echo "[init_schema] Applying development seed data..."
  psql "$CONN" -v ON_ERROR_STOP=1 -f ./schema/seed_dev.sql
fi

echo "[init_schema] Done."
