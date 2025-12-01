-- Team Status Reporter - Lightweight Dev Seed
-- Usage:
--   cd team-status-reporter-285441-285450/postgres_database
--   ./init_schema.sh --seed

-- Seed roles/permissions (optional)
INSERT INTO roles (id, name, description, created_at, updated_at)
VALUES
  (gen_random_uuid(), 'admin', 'Administrator role', NOW(), NOW()),
  (gen_random_uuid(), 'manager', 'Team manager role', NOW(), NOW()),
  (gen_random_uuid(), 'employee', 'Regular employee role', NOW(), NOW())
ON CONFLICT (name) DO NOTHING;

-- Seed users (password_hash placeholders)
WITH upsert AS (
  INSERT INTO users (id, name, email, password_hash, role, created_at, updated_at)
  VALUES
    (gen_random_uuid(), 'Mona Manager', 'manager@example.com', 'HASHED_PASSWORD_PLACEHOLDER', 'manager', NOW(), NOW()),
    (gen_random_uuid(), 'Evan Employee', 'employee@example.com', 'HASHED_PASSWORD_PLACEHOLDER', 'employee', NOW(), NOW())
  ON CONFLICT (email) DO NOTHING
  RETURNING id, email
)
SELECT 1;

-- Ensure we have ids for seeded users
WITH mgr AS (
  SELECT id AS manager_id FROM users WHERE email = 'manager@example.com'
), emp AS (
  SELECT id AS employee_id FROM users WHERE email = 'employee@example.com'
), t AS (
  INSERT INTO teams (id, name, description, created_by, created_at, updated_at)
  SELECT gen_random_uuid(), 'Core Team', 'Core engineering team', (SELECT manager_id FROM mgr), NOW(), NOW()
  ON CONFLICT (name) DO NOTHING
  RETURNING id AS team_id
), ensure_team AS (
  SELECT (SELECT team_id FROM t) AS team_id
  UNION
  SELECT id FROM teams WHERE name = 'Core Team'
), tm AS (
  INSERT INTO team_members (id, team_id, user_id, team_role, is_manager, created_at, updated_at)
  SELECT gen_random_uuid(), (SELECT team_id FROM ensure_team), (SELECT manager_id FROM mgr), 'manager', TRUE, NOW(), NOW()
  ON CONFLICT (team_id, user_id) DO NOTHING
  RETURNING id
), te AS (
  INSERT INTO team_members (id, team_id, user_id, team_role, is_manager, created_at, updated_at)
  SELECT gen_random_uuid(), (SELECT team_id FROM ensure_team), (SELECT employee_id FROM emp), 'employee', FALSE, NOW(), NOW()
  ON CONFLICT (team_id, user_id) DO NOTHING
  RETURNING id
)
SELECT 1;

-- Seed a weekly report for employee for the current week
WITH emp AS (
  SELECT id AS employee_id FROM users WHERE email = 'employee@example.com'
), tm AS (
  SELECT team_id FROM team_members WHERE user_id = (SELECT employee_id FROM emp) LIMIT 1
), cal AS (
  SELECT
    date_trunc('week', NOW())::date AS week_start,
    (date_trunc('week', NOW())::date + INTERVAL '6 days')::date AS week_end
), wr AS (
  INSERT INTO weekly_reports (id, user_id, team_id, week_start, week_end, status, notes, created_at, updated_at)
  SELECT gen_random_uuid(), (SELECT employee_id FROM emp), (SELECT team_id FROM tm), (SELECT week_start FROM cal), (SELECT week_end FROM cal), 'submitted', 'Initial seed weekly report', NOW(), NOW()
  ON CONFLICT (user_id, week_start) DO NOTHING
  RETURNING id
)
INSERT INTO report_items (id, report_id, title, description, category, effort_hours, order_index, created_at, updated_at)
SELECT
  gen_random_uuid(),
  COALESCE((SELECT id FROM wr), (SELECT id FROM weekly_reports WHERE user_id = (SELECT employee_id FROM emp) AND week_start = (SELECT week_start FROM cal))),
  'Completed onboarding tasks',
  'Reviewed codebase and set up environment.',
  'accomplishment',
  6.0,
  1,
  NOW(),
  NOW()
ON CONFLICT DO NOTHING;

-- Optional: AI summary for the seeded report
WITH emp AS (
  SELECT id AS employee_id FROM users WHERE email = 'employee@example.com'
), cal AS (
  SELECT date_trunc('week', NOW())::date AS week_start
), r AS (
  SELECT id AS report_id FROM weekly_reports WHERE user_id = (SELECT employee_id FROM emp) AND week_start = (SELECT week_start FROM cal)
)
INSERT INTO ai_summaries (id, report_id, summary_type, content, model, tokens_used, created_by, created_at, updated_at)
SELECT gen_random_uuid(), (SELECT report_id FROM r), 'weekly_summary', 'This week focused on environment setup and initial onboarding activities.', 'dev-mock', 128, (SELECT employee_id FROM emp), NOW(), NOW()
ON CONFLICT (report_id, summary_type) DO NOTHING;
