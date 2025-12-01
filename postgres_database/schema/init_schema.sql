-- Team Status Reporter - PostgreSQL Initialization Schema
-- Usage (from repository root or container):
--   cd team-status-reporter-285441-285450/postgres_database
--   ./init_schema.sh
--   ./init_schema.sh --seed
--
-- Connection hint is stored in db_connection.txt and used by init_schema.sh

-- Ensure required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Create updated_at trigger function if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'set_timestamp'
  ) THEN
    CREATE OR REPLACE FUNCTION set_timestamp()
    RETURNS TRIGGER AS $func$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $func$ LANGUAGE plpgsql;
  END IF;
END
$$;

-- Enums
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('admin', 'manager', 'employee');
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'report_status') THEN
    CREATE TYPE report_status AS ENUM ('draft', 'submitted', 'reviewed', 'approved', 'rejected');
  END IF;
END
$$;

-- Tables
-- users table (align with potential express_backend expectations)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email CITEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'employee',
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- teams
CREATE TABLE IF NOT EXISTS teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (name)
);

-- team_members (user-to-team membership, roles at team level)
CREATE TABLE IF NOT EXISTS team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_role user_role NOT NULL DEFAULT 'employee',
  is_manager BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (team_id, user_id)
);

-- weekly_reports (unique per user per week)
CREATE TABLE IF NOT EXISTS weekly_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
  week_start DATE NOT NULL,  -- Monday of the week, for example
  week_end DATE NOT NULL,    -- Sunday of the week, for example
  status report_status NOT NULL DEFAULT 'draft',
  notes TEXT,
  submitted_at TIMESTAMPTZ,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT weekly_reports_week_range_chk CHECK (week_end >= week_start),
  CONSTRAINT weekly_reports_unique_per_user_week UNIQUE (user_id, week_start)
);

-- report_items (per section or per task entries)
CREATE TABLE IF NOT EXISTS report_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES weekly_reports(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT, -- e.g., "accomplishment", "blocker", "plan"
  effort_hours NUMERIC(6,2) DEFAULT 0,
  order_index INT DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- manager_reviews (optional)
CREATE TABLE IF NOT EXISTS manager_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NOT NULL REFERENCES weekly_reports(id) ON DELETE CASCADE,
  manager_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
  comments TEXT,
  rating INT, -- 1-5 optional
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT manager_reviews_one_per_manager_per_report UNIQUE (report_id, manager_id)
);

-- activities / audit_log
CREATE TABLE IF NOT EXISTS activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  entity_type TEXT NOT NULL, -- e.g., 'weekly_report', 'report_item', 'team', 'user'
  entity_id UUID,
  action TEXT NOT NULL,      -- e.g., 'create', 'update', 'submit', 'review', 'approve', 'reject', 'delete'
  details JSONB,
  ip_address INET,
  user_agent TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- roles and permissions (optional granular RBAC beyond users.role)
CREATE TABLE IF NOT EXISTS roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (role_id, permission_id)
);

-- link users to roles (additional to basic user.role)
CREATE TABLE IF NOT EXISTS user_roles (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, role_id)
);

-- ai_summaries (storage for AI-generated text)
CREATE TABLE IF NOT EXISTS ai_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID REFERENCES weekly_reports(id) ON DELETE CASCADE,
  summary_type TEXT NOT NULL DEFAULT 'weekly_summary', -- can be 'weekly_summary', 'manager_digest', etc.
  content TEXT NOT NULL,
  model TEXT,
  tokens_used INT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL, -- who requested
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (report_id, summary_type)
);

-- export_history (PDF/Excel export records)
CREATE TABLE IF NOT EXISTS export_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
  report_id UUID REFERENCES weekly_reports(id) ON DELETE CASCADE,
  export_type TEXT NOT NULL, -- 'pdf', 'excel'
  parameters JSONB,          -- date ranges, filters, etc.
  file_url TEXT,             -- optional location of generated artifact
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);
CREATE INDEX IF NOT EXISTS idx_teams_name ON teams (name);
CREATE INDEX IF NOT EXISTS idx_team_members_team ON team_members (team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user ON team_members (user_id);
CREATE INDEX IF NOT EXISTS idx_weekly_reports_user_week ON weekly_reports (user_id, week_start);
CREATE INDEX IF NOT EXISTS idx_weekly_reports_team ON weekly_reports (team_id);
CREATE INDEX IF NOT EXISTS idx_report_items_report ON report_items (report_id);
CREATE INDEX IF NOT EXISTS idx_manager_reviews_report ON manager_reviews (report_id);
CREATE INDEX IF NOT EXISTS idx_activities_entity ON activities (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_ai_summaries_report ON ai_summaries (report_id);
CREATE INDEX IF NOT EXISTS idx_export_history_user ON export_history (user_id);

-- updated_at triggers
DO $$
BEGIN
  -- users
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_users'
  ) THEN
    CREATE TRIGGER set_timestamp_users
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- teams
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_teams'
  ) THEN
    CREATE TRIGGER set_timestamp_teams
    BEFORE UPDATE ON teams
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- team_members
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_team_members'
  ) THEN
    CREATE TRIGGER set_timestamp_team_members
    BEFORE UPDATE ON team_members
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- weekly_reports
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_weekly_reports'
  ) THEN
    CREATE TRIGGER set_timestamp_weekly_reports
    BEFORE UPDATE ON weekly_reports
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- report_items
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_report_items'
  ) THEN
    CREATE TRIGGER set_timestamp_report_items
    BEFORE UPDATE ON report_items
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- manager_reviews
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_manager_reviews'
  ) THEN
    CREATE TRIGGER set_timestamp_manager_reviews
    BEFORE UPDATE ON manager_reviews
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- roles
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_roles'
  ) THEN
    CREATE TRIGGER set_timestamp_roles
    BEFORE UPDATE ON roles
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- permissions
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_permissions'
  ) THEN
    CREATE TRIGGER set_timestamp_permissions
    BEFORE UPDATE ON permissions
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;

  -- ai_summaries
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_timestamp_ai_summaries'
  ) THEN
    CREATE TRIGGER set_timestamp_ai_summaries
    BEFORE UPDATE ON ai_summaries
    FOR EACH ROW
    EXECUTE FUNCTION set_timestamp();
  END IF;
END
$$;

-- Helpful views (optional, safe if exists)
CREATE OR REPLACE VIEW v_user_latest_report AS
SELECT
  wr.*
FROM weekly_reports wr
JOIN (
  SELECT user_id, MAX(week_start) AS max_week
  FROM weekly_reports
  GROUP BY user_id
) last ON last.user_id = wr.user_id AND last.max_week = wr.week_start;

-- Final grant (optional; assumes appuser already has db-level grants via startup.sh)
-- Adjust if needed to grant privileges on new objects:
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;
