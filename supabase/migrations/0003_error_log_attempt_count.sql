-- AutoStream observability schema (migration 0003)
-- Apply with: psql "$SUPABASE_URL" -f supabase/migrations/0003_error_log_attempt_count.sql
--   (or paste into the Supabase SQL Editor)
--
-- rules/03-workflow-design.md specifies that the shared error workflow inserts
-- error_log rows carrying attempt_count (=2 after bounded retry exhausts). The
-- 0001 schema omitted the column, so the error handler's insert referenced a
-- field that did not exist and would have been rejected. Add it to honour the
-- documented contract. Default 2 = the rule-03 max-attempts ceiling; nullable so
-- a manual insert without the field still succeeds. Table is empty, non-destructive.

alter table error_log add column if not exists attempt_count int default 2;
