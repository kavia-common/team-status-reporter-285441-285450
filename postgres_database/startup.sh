#!/bin/bash
set -euo pipefail

# Minimal PostgreSQL startup script with strict guards to avoid unintended viewer start.
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

log() { echo "[postgres_database] $*"; }

log "Starting PostgreSQL setup..."

# Discover PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1 || true)
if [ -z "${PG_VERSION}" ]; then
  log "ERROR: PostgreSQL binaries not found at /usr/lib/postgresql/"
  exit 1
fi
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
log "Found PostgreSQL version: ${PG_VERSION}"

# Function: print connection helpers
print_connection_help() {
  log "Database: ${DB_NAME}"
  log "User: ${DB_USER}"
  log "Port: ${DB_PORT}"
  echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
  if [ -f "db_connection.txt" ]; then
    echo "Or use: $(cat db_connection.txt)"
  fi
}

# If PostgreSQL is already running, exit 0 cleanly with info
if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" >/dev/null 2>&1; then
  log "PostgreSQL is already running on port ${DB_PORT}."
  print_connection_help
  log "[OK] startup.sh completed successfully (PostgreSQL already running)."
  log "[CONFIRM] Viewer startup is skipped by default; set DB_VIEWER=1 to enable."
  exit 0
fi

# Secondary check for running process (in case pg_isready has issues)
if pgrep -f "postgres.*-p ${DB_PORT}" >/dev/null 2>&1; then
  log "Detected postgres process for port ${DB_PORT}; verifying connectivity..."
  if sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d "${DB_NAME}" -c '\q' >/dev/null 2>&1; then
    log "Database ${DB_NAME} is accessible. Exiting successfully."
    print_connection_help
    log "[OK] startup.sh completed successfully (PostgreSQL already running)."
    log "[CONFIRM] Viewer startup is skipped by default; set DB_VIEWER=1 to enable."
    exit 0
  fi
fi

# Initialize data dir if needed
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
  log "Initializing PostgreSQL data directory..."
  sudo -u postgres "${PG_BIN}/initdb" -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background
log "Starting PostgreSQL server..."
sudo -u postgres "${PG_BIN}/postgres" -D /var/lib/postgresql/data -p "${DB_PORT}" &

# Wait for PostgreSQL readiness
log "Waiting for PostgreSQL to start..."
for i in {1..15}; do
  if sudo -u postgres "${PG_BIN}/pg_isready" -p "${DB_PORT}" >/dev/null 2>&1; then
    log "PostgreSQL is ready."
    break
  fi
  log "Waiting... (${i}/15)"
  sleep 2
done

# Create database (idempotent)
log "Ensuring database ${DB_NAME} exists..."
if ! sudo -u postgres "${PG_BIN}/createdb" -p "${DB_PORT}" "${DB_NAME}" 2>/dev/null; then
  log "Database may already exist."
fi

# Create/alter user and grant permissions (idempotent)
log "Ensuring user and permissions..."
sudo -u postgres "${PG_BIN}/psql" -p "${DB_PORT}" -d postgres <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
  END IF;
  ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

\\c ${DB_NAME}

GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Persist connection helpers
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
log "Connection string saved to db_connection.txt"

# Save environment variables for optional viewer usage (no start here)
mkdir -p db_visualizer
cat > db_visualizer/postgres.env <<EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF
log "Environment variables saved to db_visualizer/postgres.env"
log "To use with Node.js viewer, run: source db_visualizer/postgres.env"

# Strictly optional viewer start: only when DB_VIEWER=1 and deps available
if [ "${DB_VIEWER:-0}" = "1" ]; then
  log "DB_VIEWER=1 detected - attempting to start optional Simple DB Viewer..."
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    if [ -f "db_visualizer/package.json" ]; then
      log "Installing viewer dependencies (silent)..."
      if (cd db_visualizer && npm install --no-audit --no-fund --silent); then
        # Extra safety: ensure express is installed before attempting start
        if [ -d "db_visualizer/node_modules/express" ]; then
          log "Starting viewer in background on http://localhost:3000 ..."
          # Do not block container; suppress noisy output
          (cd db_visualizer && npm start >/dev/null 2>&1 &) || log "Warning: viewer failed to start."
        else
          log "Warning: express dependency not found after install; skipping viewer start."
        fi
      else
        log "Warning: npm install failed; viewer will not start."
      fi
    else
      log "Viewer package.json not found. Skipping viewer start."
    fi
  else
    log "Node/npm not installed. Skipping viewer start."
  fi
else
  log "DB_VIEWER is not 1; skipping optional Simple DB Viewer startup."
fi

log "PostgreSQL setup complete."
print_connection_help
log "[OK] postgres_database: startup.sh completed successfully."
log "[CONFIRM] No unconditional 'npm start' or 'node server.js' executed; db_visualizer only runs when DB_VIEWER=1 and dependencies exist."
