-- 2026-11-25 第二階段：收緊學員端權限（前提：新版前端已上線，改用 lk_login 並在請求帶 x-lk-key 標頭）
-- * 學員端(anon)不能再讀 license_keys（不能列出授權碼）、不能直接存取 key_sessions（停用直接存取，只透過 lk_login）
-- * 錯題/收藏只能存取「自己授權碼」的資料（key_id = 請求標頭 x-lk-key）
-- * study_logs 學員端只能新增、且 license_key 必須是自己的授權碼；不能讀
-- * 後台 admin.html（Supabase Auth 管理員）照常可讀寫全部
-- 回滾：本檔最下方

-- is_exam_admin() 已存在（admin@shinkong.edu.tw、bookishseven@gmail.com）

-- license_keys：學員端完全不能讀（登入改走 lk_login）
revoke all on public.license_keys from anon;
drop policy if exists anon_select on public.license_keys;
-- increment_key_used_count：lk_login 已內含，關閉對外呼叫
revoke execute on function public.increment_key_used_count(uuid) from public, anon, authenticated;

do $$
declare t text; p record;
begin
  foreach t in array array['key_sessions', 'key_wrong_answers', 'key_favorites', 'study_logs'] loop
    -- 拿掉所有給學員端的舊 policy（client_all / anon_*）
    for p in select policyname from pg_policies
              where schemaname = 'public' and tablename = t
                and policyname not in ('admin_all') loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format('create policy admin_all on public.%I for all to authenticated
                      using (public.is_exam_admin()) with check (public.is_exam_admin())', t);
  end loop;
end $$;

-- 錯題 / 收藏：只能存取自己的
create policy lk_own on public.key_wrong_answers for all to anon
  using (key_id = public.lk_request_key()) with check (key_id = public.lk_request_key());
create policy lk_own on public.key_favorites for all to anon
  using (key_id = public.lk_request_key()) with check (key_id = public.lk_request_key());
-- study_logs：只能新增自己的紀錄
create policy lk_insert_own on public.study_logs for insert to anon
  with check (license_key = public.lk_request_key_code());

-- key_sessions：學員端沒有任何 policy（只透過 security definer 的 lk_login 存取）
revoke all on public.key_sessions from anon;

/* ── 回滾（需要時才用，會回到第二階段之前的全開狀態）──
grant execute on function public.increment_key_used_count(uuid) to anon, authenticated;
grant select (id, key_code, batch_name, max_uses, used_count, expires_at, is_active) on public.license_keys to anon;
create policy anon_select on public.license_keys for select to anon using (true);
grant select, insert, update, delete on public.key_sessions to anon;
do $$ declare t text; begin
  foreach t in array array['key_sessions', 'key_wrong_answers', 'key_favorites', 'study_logs'] loop
    execute format('drop policy if exists lk_own on public.%I', t);
    execute format('drop policy if exists lk_insert_own on public.%I', t);
    execute format('create policy client_all on public.%I for all to anon using (true) with check (true)', t);
  end loop; end $$;
*/
