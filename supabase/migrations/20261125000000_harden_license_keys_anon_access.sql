-- 2026-11-25 授權碼資安修補（已在正式資料庫套用：LIFE/FX 由 Claude 套用，INV 由 Eric 在 SQL Editor 執行）
-- 問題：學員端(anon)可以呼叫 increment_key_used_count 無限灌 used_count、可讀 license_keys 的 notes。

-- 1) used_count 只會等於實際登入裝置數，重複呼叫不會灌數字
create or replace function public.increment_key_used_count(k_id uuid)
returns void language sql security definer set search_path to 'public' as $$
  update public.license_keys k
     set used_count = greatest(k.used_count,
           (select count(*) from public.key_sessions s where s.key_id = k.id))
   where k.id = k_id;
$$;

-- 2) 學員端只能讀登入需要的欄位，不能讀 notes、不能寫
revoke all on public.license_keys from anon;
grant select (id, key_code, batch_name, max_uses, used_count, expires_at, is_active)
  on public.license_keys to anon;
