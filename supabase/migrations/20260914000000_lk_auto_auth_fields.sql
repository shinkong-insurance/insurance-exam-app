alter table public.students
  add column if not exists exam_date date,
  add column if not exists referrer_unit text,
  add column if not exists referrer_id text;

-- Non-unique: existing rows may have duplicate/blank phone numbers already,
-- so this is a lookup-speed index, not a uniqueness constraint. The
-- "same phone = same person" rule is enforced in application code
-- (auto-register-student Edge Function), not the database.
create index if not exists students_phone_idx on public.students (phone);
