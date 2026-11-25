-- 2026-11-25 第一階段（只新增，不移除任何既有權限；舊版前端照常可用）
-- 1) lk_login：授權碼登入改由伺服器端驗證，前端不再直接讀 license_keys / key_sessions
-- 2) lk_request_key / lk_request_key_code：從請求標頭 x-lk-key 取得「目前登入的授權碼」，
--    第二階段的 RLS 用它把錯題/收藏/關卡/作答紀錄限縮成「只能存取自己的」

create or replace function public.lk_request_key()
returns uuid language sql stable set search_path = public as $$
  select case
           when h ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then h::uuid
         end
    from (select lower(coalesce(
            nullif(current_setting('request.headers', true), '')::json ->> 'x-lk-key', '')) as h) s;
$$;

create or replace function public.lk_request_key_code()
returns text language sql stable security definer set search_path = public as $$
  select key_code from public.license_keys where id = public.lk_request_key();
$$;

create or replace function public.lk_login(p_code text, p_device text)
returns json language plpgsql security definer set search_path = public as $$
declare
  k record;
  s_id uuid;
  max_u int;
begin
  if p_device is null or length(p_device) < 4 or length(p_device) > 100 then
    return json_build_object('result', 'error');
  end if;

  select id, key_code, batch_name, max_uses, used_count, expires_at, is_active
    into k
    from public.license_keys
   where key_code = upper(trim(p_code));

  if not found then
    return json_build_object('result', 'not_found');
  end if;
  if k.is_active = false then
    return json_build_object('result', 'disabled');
  end if;
  if k.expires_at < now() then
    return json_build_object('result', 'expired', 'expires_at', k.expires_at);
  end if;

  max_u := coalesce(k.max_uses, 1);          -- 0 = 無限
  select id into s_id from public.key_sessions
   where key_id = k.id and device_id = p_device limit 1;

  -- 每裝置獨立計算，同裝置再次登入不佔用名額（與舊版前端邏輯相同）
  if max_u > 0 and s_id is null and coalesce(k.used_count, 0) >= max_u then
    return json_build_object('result', 'max_used');
  end if;

  if s_id is null then
    insert into public.key_sessions (key_id, device_id, login_count)
    values (k.id, p_device, 1);
    if max_u > 0 then
      update public.license_keys
         set used_count = greatest(used_count,
               (select count(*) from public.key_sessions where key_id = k.id))
       where id = k.id;
    end if;
  else
    update public.key_sessions
       set login_count = coalesce(login_count, 0) + 1, last_used_at = now()
     where id = s_id;
  end if;

  return json_build_object(
    'result', 'success',
    'id', k.id,
    'key_code', k.key_code,
    'batch_name', k.batch_name,
    'expires_at', k.expires_at);
end;
$$;

revoke all on function public.lk_login(text, text) from public;
grant execute on function public.lk_login(text, text) to anon, authenticated;
revoke all on function public.lk_request_key_code() from public;
grant execute on function public.lk_request_key_code() to anon, authenticated;
grant execute on function public.lk_request_key() to anon, authenticated;
