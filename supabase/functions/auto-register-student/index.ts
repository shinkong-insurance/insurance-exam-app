import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })
}

function generateKeyCode(): string {
  const year = new Date().getFullYear()
  const alpha = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  const rand4a = Array.from({ length: 4 }, () => alpha[Math.floor(Math.random() * alpha.length)]).join('')
  const rand4n = String(Math.floor(Math.random() * 10000)).padStart(4, '0')
  return `SK-${year}-${rand4a}-${rand4n}`
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS })
  if (req.method !== 'POST') return jsonResponse({ error: 'Method not allowed' }, 405)

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ error: '請求格式錯誤' }, 400)
  }

  const name = String(body.name ?? '').trim()
  const phone = String(body.phone ?? '').trim()
  const examDate = String(body.exam_date ?? '').trim()
  const referrerName = body.referrer_name ? String(body.referrer_name).trim() : null
  const referrerPhone = body.referrer_phone ? String(body.referrer_phone).trim() : null
  const referrerUnit = body.referrer_unit ? String(body.referrer_unit).trim() : null
  const referrerId = body.referrer_id ? String(body.referrer_id).trim() : null

  if (!name) return jsonResponse({ error: '請填寫姓名' }, 400)
  if (!phone) return jsonResponse({ error: '請填寫電話' }, 400)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(examDate)) return jsonResponse({ error: '考試日期格式錯誤' }, 400)

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  const expiresAtDate = new Date()
  expiresAtDate.setDate(expiresAtDate.getDate() + 60)
  const expiresAtIso = expiresAtDate.toISOString()

  const { data: existing, error: findErr } = await sb
    .from('students')
    .select('id, key_id, key_code')
    .eq('phone', phone)
    .maybeSingle()

  if (findErr) return jsonResponse({ error: findErr.message }, 500)

  // Generates and inserts a fresh, unique license_keys row; retries on the
  // (rare) key_code collision.
  async function createLicenseKey(): Promise<{ id: string; keyCode: string } | { error: string }> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = generateKeyCode()
      const { data: inserted, error: insKeyErr } = await sb
        .from('license_keys')
        .insert({
          key_code: candidate,
          batch_name: 'AUTO',
          max_uses: 0,
          expires_at: expiresAtIso,
          is_active: true,
        })
        .select('id, key_code')
        .single()
      if (!insKeyErr) return { id: inserted.id, keyCode: inserted.key_code }
      if (!insKeyErr.message?.includes('23505')) return { error: insKeyErr.message }
    }
    return { error: '授權碼產生失敗，請重試' }
  }

  if (existing) {
    // A student row can exist without a key_id (e.g. added manually via
    // admin.html without assigning a key yet) — generate one now rather
    // than returning a null key_id/key_code to the client.
    let keyId = existing.key_id as string | null
    let keyCode = existing.key_code as string | null

    if (!keyId) {
      const created = await createLicenseKey()
      if ('error' in created) return jsonResponse({ error: created.error }, 500)
      keyId = created.id
      keyCode = created.keyCode
    } else {
      const { error: updKeyErr } = await sb
        .from('license_keys')
        .update({ expires_at: expiresAtIso, is_active: true })
        .eq('id', keyId)
      if (updKeyErr) return jsonResponse({ error: updKeyErr.message }, 500)
    }

    const { error: updStudentErr } = await sb
      .from('students')
      .update({
        name,
        exam_date: examDate,
        referrer: referrerName,
        referrer_phone: referrerPhone,
        referrer_unit: referrerUnit,
        referrer_id: referrerId,
        key_id: keyId,
        key_code: keyCode,
        expires_at: expiresAtIso,
        is_active: true,
      })
      .eq('id', existing.id)
    if (updStudentErr) return jsonResponse({ error: updStudentErr.message }, 500)

    return jsonResponse({ key_id: keyId, key_code: keyCode, expires_at: expiresAtIso })
  }

  const created = await createLicenseKey()
  if ('error' in created) return jsonResponse({ error: created.error }, 500)
  const { id: keyId, keyCode } = created

  const { error: insStudentErr } = await sb.from('students').insert({
    name,
    phone,
    exam_date: examDate,
    referrer: referrerName,
    referrer_phone: referrerPhone,
    referrer_unit: referrerUnit,
    referrer_id: referrerId,
    key_id: keyId,
    key_code: keyCode,
    expires_at: expiresAtIso,
    is_active: true,
  })
  if (insStudentErr) return jsonResponse({ error: insStudentErr.message }, 500)

  return jsonResponse({ key_id: keyId, key_code: keyCode, expires_at: expiresAtIso })
})
