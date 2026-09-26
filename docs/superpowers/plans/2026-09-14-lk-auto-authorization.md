# `#/lk` 自動授權 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual "teacher issues a license key" flow at `#/lk` with a self-service form (name/phone/exam date/referrer info) that auto-grants 60 days of access, and add delete + statistics to the teacher backend (`admin.html`) that already manages this data.

**Architecture:** A new Supabase Edge Function (`auto-register-student`) does all writes with the service-role key: it looks a student up by phone, and either inserts a new `students` + `license_keys` row or renews an existing one (expiry reset to now+60 days). The Flutter `/lk` gate page calls this function and logs the student straight in — no key code is ever shown. The existing manual/batch key-generation path in `admin.html` is untouched, kept as a backup path. `admin.html` gets three additions: new field columns, delete buttons (with the necessary `key_sessions` cleanup), and extra stats/groupings.

**Tech Stack:** Flutter (Dart, go_router, supabase_flutter), Supabase Postgres + Edge Functions (Deno/TypeScript), static HTML/JS admin panel (`admin.html`), Supabase JS client v2 (loaded from jsDelivr in the static pages).

**Spec:** `docs/superpowers/specs/2026-09-14-lk-auto-authorization-design.md`

## Global Constraints

- Auto-granted access is always exactly **60 days** from the moment of submission (`now + 60 days`), recalculated on every resubmission by the same phone number — never additive, never capped elsewhere.
- The registration form has exactly these fields: 姓名 (name, required), 電話 (phone, required), 考試日期 (exam date, required, dropdown of the next 61 days), 推薦人姓名, 推薦人電話, 推薦人單位, 推薦人員編 (all four referrer fields optional). No region/unit/email fields on this form.
- Same phone number = same person: the Edge Function looks up `students` by `phone` and updates that row instead of inserting a duplicate.
- No license key is ever displayed to the student or emailed for this flow — successful submission logs the student straight into `/`.
- The existing manual/batch key-generation UI and logic in `admin.html` (`saveKey`, `toggleKey`, `doBatchGenerate`, etc.) must keep working unmodified.
- New Edge Function uses the **service-role key** server-side only; the Flutter client and static pages never gain direct write access to `students`/`license_keys` beyond what they already have.
- Every destructive action added to `admin.html` (student delete, key delete) must show a `confirm()` dialog before calling Supabase.

---

## Task 1: Supabase schema migration — new `students` columns

**Files:**
- Create: `supabase/migrations/20260914000000_lk_auto_auth_fields.sql`

**Interfaces:**
- Produces: `students.exam_date` (date), `students.referrer_unit` (text), `students.referrer_id` (text) columns, plus a non-unique index on `students.phone` — all later tasks read/write these.

- [ ] **Step 1: Write the migration SQL**

```sql
-- supabase/migrations/20260914000000_lk_auto_auth_fields.sql
alter table public.students
  add column if not exists exam_date date,
  add column if not exists referrer_unit text,
  add column if not exists referrer_id text;

-- Non-unique: existing rows may have duplicate/blank phone numbers already,
-- so this is a lookup-speed index, not a uniqueness constraint. The
-- "same phone = same person" rule is enforced in application code
-- (auto-register-student Edge Function), not the database.
create index if not exists students_phone_idx on public.students (phone);
```

- [ ] **Step 2: Apply the migration via the Supabase Dashboard SQL Editor**

This project has no `supabase/` folder or CLI link set up yet, and applying
migrations via `supabase db push` requires the database password (not just
an access token), which is out of scope to acquire here. Instead:

1. Open `https://supabase.com/dashboard/project/kbclpucolchpwykqciyw/sql/new`
   (same project referenced in `lib/core/services/supabase_config.dart:4-6`
   and `admin.html:394`).
2. Paste the contents of `supabase/migrations/20260914000000_lk_auto_auth_fields.sql`
   and run it.
3. Confirm success: run `select column_name from information_schema.columns
   where table_name = 'students' and column_name in ('exam_date',
   'referrer_unit', 'referrer_id');` — expect 3 rows back.

- [ ] **Step 3: Commit the migration file**

```bash
git add supabase/migrations/20260914000000_lk_auto_auth_fields.sql
git commit -m "chore: add students.exam_date/referrer_unit/referrer_id migration"
```

---

## Task 2: `auto-register-student` Edge Function

**Files:**
- Create: `supabase/functions/auto-register-student/index.ts`

**Interfaces:**
- Consumes: `students` / `license_keys` tables (columns from Task 1 must already exist in the live database).
- Produces: a deployed HTTPS endpoint at
  `https://kbclpucolchpwykqciyw.supabase.co/functions/v1/auto-register-student`
  accepting `POST { name, phone, exam_date, referrer_name?, referrer_phone?,
  referrer_unit?, referrer_id? }` and returning `{ key_id, key_code,
  expires_at }` on success or `{ error: string }` (non-2xx) on failure. Task 3
  (`LkAuthService.autoRegister`) calls this exact shape.

- [ ] **Step 1: Write the function**

```typescript
// supabase/functions/auto-register-student/index.ts
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
```

- [ ] **Step 2: Log in and link the Supabase CLI (one-time, interactive)**

This requires the user to run this themselves since it opens a browser for
auth — hand off with a clear message rather than attempting it as an agent:

```bash
supabase login
supabase link --project-ref kbclpucolchpwykqciyw
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` do not need to be set manually —
Supabase automatically injects them into every deployed Edge Function's
environment.

- [ ] **Step 3: Deploy the function**

```bash
supabase functions deploy auto-register-student --no-verify-jwt
```

`--no-verify-jwt` is required because this is a public self-service endpoint
called with the anon key from an unauthenticated student, matching how
`register.html` already calls `register-student` today.

- [ ] **Step 4: Manually verify against the live function**

```bash
# New phone number → expect { key_id, key_code, expires_at } with expires_at ~60 days out
curl -s -X POST \
  'https://kbclpucolchpwykqciyw.supabase.co/functions/v1/auto-register-student' \
  -H 'Content-Type: application/json' \
  -H 'apikey: <ANON_KEY from admin.html:395>' \
  -d '{"name":"測試學員","phone":"0912345678","exam_date":"2026-10-01","referrer_name":"介紹人A","referrer_phone":"0922222222","referrer_unit":"忠孝通訊處","referrer_id":"E12345"}'

# Same phone again → expect the SAME key_code, expires_at recalculated to ~60 days from now
curl -s -X POST \
  'https://kbclpucolchpwykqciyw.supabase.co/functions/v1/auto-register-student' \
  -H 'Content-Type: application/json' \
  -H 'apikey: <ANON_KEY from admin.html:395>' \
  -d '{"name":"測試學員","phone":"0912345678","exam_date":"2026-11-01"}'

# Missing name → expect 400 { "error": "請填寫姓名" }
curl -s -X POST \
  'https://kbclpucolchpwykqciyw.supabase.co/functions/v1/auto-register-student' \
  -H 'Content-Type: application/json' \
  -H 'apikey: <ANON_KEY from admin.html:395>' \
  -d '{"name":"","phone":"0912345678","exam_date":"2026-10-01"}'
```

Then check `admin.html` → 學員管理 tab and confirm the test row(s) appear with
the right `expires_at`, and delete the test row(s) once confirmed (delete UI
lands in Task 6 — until then, delete manually via the Dashboard's table
editor).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/auto-register-student/index.ts
git commit -m "feat: add auto-register-student edge function"
```

---

## Task 3: Exam-date dropdown helper (pure function, unit tested)

**Files:**
- Create: `lib/core/utils/exam_date_options.dart`
- Test: `test/core/utils/exam_date_options_test.dart`

**Interfaces:**
- Produces: `List<DateTime> examDateOptions({DateTime? now})` — Task 5's UI
  consumes this directly.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/utils/exam_date_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insurance_exam_app/core/utils/exam_date_options.dart';

void main() {
  test('returns 61 consecutive dates starting today, time stripped', () {
    final now = DateTime(2026, 9, 14, 15, 30);
    final options = examDateOptions(now: now);

    expect(options.length, 61);
    expect(options.first, DateTime(2026, 9, 14));
    expect(options.last, DateTime(2026, 11, 13));
    expect(options[1], DateTime(2026, 9, 15));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/exam_date_options_test.dart`
Expected: FAIL — `Error: Not found: 'package:insurance_exam_app/core/utils/exam_date_options.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/utils/exam_date_options.dart
List<DateTime> examDateOptions({DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  return List.generate(61, (i) => today.add(Duration(days: i)));
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String formatExamDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/exam_date_options_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/exam_date_options.dart test/core/utils/exam_date_options_test.dart
git commit -m "feat: add exam date dropdown option helper"
```

---

## Task 4: `LkAuthService.autoRegister()`

**Files:**
- Modify: `lib/core/services/lk_auth_service.dart`

**Interfaces:**
- Consumes: Supabase Edge Function `auto-register-student` (Task 2); reuses
  existing `LkLoginResponse`/`LkLoginResult` types already in this file
  (`lk_auth_service.dart:8-26`).
- Produces: `static Future<LkLoginResponse> autoRegister({required String
  name, required String phone, required DateTime examDate, String?
  referrerName, String? referrerPhone, String? referrerUnit, String?
  referrerId})` — Task 5's `lk_gate_page.dart` calls this exact signature.

There is no existing test scaffolding for Supabase-backed services in this
project (`test/` only contains the default `widget_test.dart` counter smoke
test, no mocking library in `pubspec.yaml`). Introducing a mocking framework
is out of scope for this feature — verify this method the same way `login()`
is verified today: manually, end-to-end, once Task 5's UI can call it (see
Task 5's manual verification step).

- [ ] **Step 1: Add the import and method**

Add `import '../utils/exam_date_options.dart';` is NOT needed here (date
formatting is done by the caller in Task 5); only add the new method.

Insert after the existing `login()` method (after `lk_auth_service.dart:119`,
before the `_upsertSession` helper):

```dart
  // ── 自動註冊（免碼登入）────────────────────────
  static Future<LkLoginResponse> autoRegister({
    required String name,
    required String phone,
    required DateTime examDate,
    String? referrerName,
    String? referrerPhone,
    String? referrerUnit,
    String? referrerId,
  }) async {
    try {
      final examDateStr =
          '${examDate.year.toString().padLeft(4, '0')}-'
          '${examDate.month.toString().padLeft(2, '0')}-'
          '${examDate.day.toString().padLeft(2, '0')}';

      final res = await _sb.functions.invoke('auto-register-student', body: {
        'name': name,
        'phone': phone,
        'exam_date': examDateStr,
        'referrer_name': referrerName,
        'referrer_phone': referrerPhone,
        'referrer_unit': referrerUnit,
        'referrer_id': referrerId,
      });

      final data = res.data;
      if (data is! Map || data['error'] != null) {
        final msg = (data is Map ? data['error']?.toString() : null) ?? '註冊失敗，請稍後再試';
        return LkLoginResponse(result: LkLoginResult.error, error: msg);
      }

      final keyId = data['key_id'] as String;
      final keyCode = data['key_code'] as String;
      final expiresAt = DateTime.parse(data['expires_at'] as String);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLkKeyId, keyId);
      await prefs.setString(_kLkKeyCode, keyCode);
      await prefs.setString(_kLkBatchName, 'AUTO');
      await prefs.setString(_kLkExpiresAt, expiresAt.toIso8601String());
      await prefs.setBool(_kLkLoggedIn, true);

      return LkLoginResponse(
        result: LkLoginResult.success,
        keyId: keyId,
        keyCode: keyCode,
        batchName: 'AUTO',
        expiresAt: expiresAt,
      );
    } catch (e) {
      return LkLoginResponse(result: LkLoginResult.error, error: e.toString());
    }
  }
```

- [ ] **Step 2: Confirm the project compiles**

Run: `flutter analyze lib/core/services/lk_auth_service.dart`
Expected: No errors (warnings pre-existing in the file, if any, are fine).

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/lk_auth_service.dart
git commit -m "feat: add LkAuthService.autoRegister"
```

---

## Task 5: `lk_gate_page.dart` dual-mode UI

**Files:**
- Modify: `lib/features/auth/lk_gate_page.dart` (full rewrite of the file)

**Interfaces:**
- Consumes: `LkAuthService.autoRegister(...)` (Task 4), `LkAuthService.login(String)`
  (existing, unchanged), `examDateOptions()`/`formatExamDate()` (Task 3).

- [ ] **Step 1: Replace the file contents**

```dart
// lib/features/auth/lk_gate_page.dart
// #/lk 入口：預設為自動註冊表單，另提供「使用授權碼登入」備用路徑

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/lk_auth_service.dart';
import '../../core/services/study_logger.dart';
import '../../core/utils/exam_date_options.dart';

class LkGatePage extends StatefulWidget {
  const LkGatePage({super.key});

  @override
  State<LkGatePage> createState() => _LkGatePageState();
}

class _LkGatePageState extends State<LkGatePage> {
  // 授權碼登入（備用路徑）
  final _codeCtrl = TextEditingController();

  // 自動註冊表單
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _referrerNameCtrl = TextEditingController();
  final _referrerPhoneCtrl = TextEditingController();
  final _referrerUnitCtrl = TextEditingController();
  final _referrerIdCtrl = TextEditingController();
  late final List<DateTime> _examDateOptions;
  DateTime? _selectedExamDate;

  bool _showKeyLogin = false;
  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _examDateOptions = examDateOptions();
    _selectedExamDate = _examDateOptions.first;
    _checkExistingSession();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _referrerNameCtrl.dispose();
    _referrerPhoneCtrl.dispose();
    _referrerUnitCtrl.dispose();
    _referrerIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    final session = await LkAuthService.getSession();
    if (session != null && mounted) {
      context.go('/');
    }
  }

  Future<void> _submitRegister() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMsg = '請填寫姓名');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _errorMsg = '請填寫電話');
      return;
    }
    if (_selectedExamDate == null) {
      setState(() => _errorMsg = '請選擇考試日期');
      return;
    }

    setState(() { _loading = true; _errorMsg = null; });

    final res = await LkAuthService.autoRegister(
      name: name,
      phone: phone,
      examDate: _selectedExamDate!,
      referrerName: _referrerNameCtrl.text.trim().isEmpty ? null : _referrerNameCtrl.text.trim(),
      referrerPhone: _referrerPhoneCtrl.text.trim().isEmpty ? null : _referrerPhoneCtrl.text.trim(),
      referrerUnit: _referrerUnitCtrl.text.trim().isEmpty ? null : _referrerUnitCtrl.text.trim(),
      referrerId: _referrerIdCtrl.text.trim().isEmpty ? null : _referrerIdCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res.result == LkLoginResult.success) {
      StudyLogger.login(res.keyCode ?? '');
      context.go('/');
    } else {
      setState(() => _errorMsg = res.error ?? '註冊失敗，請稍後再試');
    }
  }

  Future<void> _loginWithCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMsg = '請輸入授權碼');
      return;
    }
    if (!RegExp(r'^SK-\d{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(code)) {
      setState(() => _errorMsg = '授權碼格式不正確\n範例：SK-2026-ABCD-1234');
      return;
    }

    setState(() { _loading = true; _errorMsg = null; });

    final res = await LkAuthService.login(code);

    if (!mounted) return;
    setState(() => _loading = false);

    switch (res.result) {
      case LkLoginResult.success:
        StudyLogger.login(res.keyCode ?? code);
        context.go('/');
      case LkLoginResult.notFound:
        setState(() => _errorMsg = '找不到此授權碼，請確認後重試');
      case LkLoginResult.expired:
        setState(() => _errorMsg = '此授權碼已於 ${res.expiresAt?.toLocal().toString().substring(0,10)} 到期');
      case LkLoginResult.maxUsed:
        setState(() => _errorMsg = '此授權碼使用名額已滿，請洽管理人員');
      case LkLoginResult.disabled:
        setState(() => _errorMsg = '此授權碼已停用，請洽管理人員');
      case LkLoginResult.error:
        setState(() => _errorMsg = '驗證失敗：${res.error}');
    }
  }

  void _toggleMode() {
    setState(() {
      _showKeyLogin = !_showKeyLogin;
      _errorMsg = null;
    });
  }

  InputDecoration _fieldDecoration(String label, {bool required = false}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF16213E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '學員報名',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          '填寫以下資料即可自動取得 60 天使用權限',
          style: TextStyle(color: Colors.white60, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          enabled: !_loading,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('姓名', required: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('電話', required: true),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<DateTime>(
          value: _selectedExamDate,
          isExpanded: true,
          dropdownColor: const Color(0xFF16213E),
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('考試日期', required: true),
          items: _examDateOptions
              .map((d) => DropdownMenuItem(value: d, child: Text(formatExamDate(d))))
              .toList(),
          onChanged: _loading ? null : (d) => setState(() => _selectedExamDate = d),
        ),
        const SizedBox(height: 20),
        const Text('推薦人資訊（選填）', style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _referrerNameCtrl,
          enabled: !_loading,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('推薦人姓名'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _referrerPhoneCtrl,
          enabled: !_loading,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('推薦人電話'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _referrerUnitCtrl,
          enabled: !_loading,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('推薦人單位'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _referrerIdCtrl,
          enabled: !_loading,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('推薦人員編'),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _submitRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('送出並開始學習'),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : _toggleMode,
          child: const Text('改用授權碼登入', style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }

  Widget _buildKeyLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(color: Colors.teal.shade700, shape: BoxShape.circle),
            child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '保險業務員資格測驗',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Text(
          '請輸入課程授權碼以開始學習',
          style: TextStyle(color: Colors.white60, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        const Text('授權碼', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _errorMsg != null ? Colors.red.shade400 : Colors.white24),
          ),
          child: TextField(
            controller: _codeCtrl,
            enabled: !_loading,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 18, letterSpacing: 2),
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: 'SK-2026-ABCD-1234',
              hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              LengthLimitingTextInputFormatter(17),
              _LkFormatter(),
            ],
            onSubmitted: (_) => _loginWithCode(),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '授權碼由教育訓練單位提供，格式為 SK-YYYY-XXXX-NNNN',
          style: TextStyle(color: Colors.white38, fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _loginWithCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('驗證授權碼並進入'),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : _toggleMode,
          child: const Text('改用學員報名表單', style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _showKeyLogin ? _buildKeyLoginForm() : _buildRegisterForm(),
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Tooltip(
                  message: '管理員後台',
                  child: IconButton(
                    icon: const Icon(Icons.admin_panel_settings, color: Colors.white12, size: 22),
                    onPressed: () => context.push('/admin-login'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LkFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase().replaceAll('-', '');
    final buf = StringBuffer();
    for (int i = 0; i < text.length && i < 14; i++) {
      if (i == 2 || i == 6 || i == 10) buf.write('-');
      buf.write(text[i]);
    }
    final result = buf.toString();
    return newValue.copyWith(text: result, selection: TextSelection.collapsed(offset: result.length));
  }
}
```

- [ ] **Step 2: Static-check the file**

Run: `flutter analyze lib/features/auth/lk_gate_page.dart`
Expected: No errors.

- [ ] **Step 3: Manual verification**

```bash
flutter run -d chrome
```

Navigate to `/#/lk`. Confirm: the registration form shows by default with all
7 fields; submitting with a fresh phone number logs straight into `/` (no key
code shown anywhere); clicking "改用授權碼登入" swaps to the original code
box and back; submitting the same phone number twice in a row logs in both
times without error.

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/lk_gate_page.dart
git commit -m "feat: add auto-registration form to #/lk gate page"
```

---

## Task 6: `admin.html` — display new fields

**Files:**
- Modify: `admin.html:184-198` (table header + row rendering), `admin.html:246-296` (add/edit modal)

**Interfaces:**
- Consumes: `students.exam_date`, `students.referrer_unit`, `students.referrer_id`
  (Task 1), plus the already-existing `students.referrer` / `students.referrer_phone`
  columns (written by `register.html` today, confirmed via `register.html:279`).

- [ ] **Step 1: Add table header columns**

In `admin.html`, replace the header block at lines 184-195:

```html
              <tr>
                <th class="hide-sm">區部</th>
                <th class="hide-sm">單位</th>
                <th>姓名</th>
                <th class="hide-sm">電話</th>
                <th class="hide-sm">考試日期</th>
                <th class="hide-sm">推薦人</th>
                <th class="hide-sm">推薦單位</th>
                <th>授權碼</th>
                <th class="hide-sm">到期日</th>
                <th>狀態</th>
                <th>操作</th>
              </tr>
```

(This drops the 信箱/梯次/寄送 columns from the visible table since the new
flow doesn't collect email — the "寄送" send-email action in `sendLicenseEmail()`
still works for any student that does have an email/key_code from the legacy
manual path, it's just no longer a dedicated column; keep a compact 操作 cell
that shows the 寄送 button conditionally, same condition as today.)

- [ ] **Step 2: Update `renderTable()` row building**

Replace the row-building block at `admin.html:533-632` with:

```javascript
  const rows = filtered.map(u => {
    const exp = u.expires_at ? new Date(u.expires_at) : null;
    const isExp = exp && exp <= now;
    const daysLeft = exp ? Math.ceil((exp - now) / 86400000) : null;
    let badgeText, badgeClass;
    if (!u.is_active)      { badgeText = '已停用'; badgeClass = 'badge-red'; }
    else if (!u.key_code)  { badgeText = '未分配'; badgeClass = 'badge-warn'; }
    else if (isExp)        { badgeText = '已到期'; badgeClass = 'badge-warn'; }
    else if (daysLeft <= 7){ badgeText = '剩 ' + daysLeft + ' 天'; badgeClass = 'badge-warn'; }
    else                   { badgeText = '有效'; badgeClass = 'badge-green'; }

    const tr = document.createElement('tr');

    const tdRegion = document.createElement('td');
    tdRegion.className = 'hide-sm';
    tdRegion.textContent = u.region || '—';

    const tdUnit = document.createElement('td');
    tdUnit.className = 'hide-sm';
    tdUnit.textContent = u.unit_name || '—';

    const tdName = document.createElement('td');
    const strong = document.createElement('strong');
    strong.textContent = u.name;
    tdName.appendChild(strong);

    const tdPhone = document.createElement('td');
    tdPhone.className = 'hide-sm';
    tdPhone.textContent = u.phone || '—';

    const tdExamDate = document.createElement('td');
    tdExamDate.className = 'hide-sm';
    tdExamDate.textContent = u.exam_date || '—';

    const tdReferrer = document.createElement('td');
    tdReferrer.className = 'hide-sm';
    tdReferrer.textContent = u.referrer
      ? (u.referrer + (u.referrer_id ? '（' + u.referrer_id + '）' : ''))
      : '—';

    const tdReferrerUnit = document.createElement('td');
    tdReferrerUnit.className = 'hide-sm';
    tdReferrerUnit.textContent = u.referrer_unit || '—';

    const tdKey = document.createElement('td');
    if (u.key_code) {
      const span = document.createElement('span');
      span.className = 'key-code';
      span.title = '點擊複製';
      span.textContent = u.key_code;
      span.onclick = () => navigator.clipboard.writeText(u.key_code);
      tdKey.appendChild(span);
    } else {
      tdKey.textContent = '—';
    }

    const tdExp = document.createElement('td');
    tdExp.className = 'hide-sm';
    tdExp.textContent = u.expires_at?.substring(0,10) || '—';

    const tdBadge = document.createElement('td');
    const badge = document.createElement('span');
    badge.className = 'badge ' + badgeClass;
    badge.textContent = badgeText;
    tdBadge.appendChild(badge);

    const tdOps = document.createElement('td');

    const editBtn = document.createElement('button');
    editBtn.className = 'btn btn-outline btn-sm';
    editBtn.textContent = '編輯';
    editBtn.onclick = () => openEditUserModal(u.id);
    tdOps.appendChild(editBtn);

    const toggleBtn = document.createElement('button');
    toggleBtn.className = u.is_active ? 'btn btn-danger btn-sm' : 'btn btn-outline btn-sm';
    toggleBtn.style.marginLeft = '4px';
    toggleBtn.textContent = u.is_active ? '停用' : '啟用';
    toggleBtn.onclick = () => toggleUser(u.id, !u.is_active);
    tdOps.appendChild(toggleBtn);

    if (u.email && u.key_code) {
      const sendBtn = document.createElement('button');
      sendBtn.className = 'btn btn-info btn-sm';
      sendBtn.style.marginLeft = '4px';
      sendBtn.textContent = u.email_sent_at ? '重寄' : '寄送';
      sendBtn.onclick = () => sendLicenseEmail(u.id);
      tdOps.appendChild(sendBtn);
    }

    const deleteBtn = document.createElement('button');
    deleteBtn.className = 'btn btn-danger btn-sm';
    deleteBtn.style.marginLeft = '4px';
    deleteBtn.textContent = '刪除';
    deleteBtn.onclick = () => deleteUser(u.id);
    tdOps.appendChild(deleteBtn);

    tr.append(tdRegion, tdUnit, tdName, tdPhone, tdExamDate, tdReferrer, tdReferrerUnit, tdKey, tdExp, tdBadge, tdOps);
    return tr;
  });
```

(`deleteUser` is added in Task 7 — this step references it, but Task 7's
addition must land before this is functional; if executing tasks strictly in
order this is fine since Task 7 comes right after.)

Also update the two `colspan` attributes at `admin.html:482` and `admin.html:524`
from `'10'` to `'11'` to match the new column count.

- [ ] **Step 3: Add exam date / referrer unit / referrer id fields to the add/edit modal**

In `admin.html`, insert into the `user-modal` block (after the 梯次/到期日 row,
before the 指定授權碼 row — i.e. after line 279, before line 280):

```html
    <div class="form-row-2">
      <div>
        <label>考試日期</label>
        <input type="date" id="f-exam-date">
      </div>
      <div>
        <label>推薦人單位</label>
        <input type="text" id="f-referrer-unit" placeholder="選填">
      </div>
    </div>
    <div class="form-row-2">
      <div>
        <label>推薦人姓名</label>
        <input type="text" id="f-referrer" placeholder="選填">
      </div>
      <div>
        <label>推薦人電話</label>
        <input type="text" id="f-referrer-phone" placeholder="選填">
      </div>
    </div>
    <div class="form-row">
      <label>推薦人員編</label>
      <input type="text" id="f-referrer-id" placeholder="選填">
    </div>
```

- [ ] **Step 4: Wire the new fields into `openAddUserModal`/`openEditUserModal`/`saveUser`**

In `openAddUserModal()` (`admin.html:676-685`), extend the field-clearing array:

```javascript
  ['f-region','f-unit','f-name','f-email','f-batch-name','f-notes',
   'f-exam-date','f-referrer-unit','f-referrer','f-referrer-phone','f-referrer-id']
    .forEach(id => document.getElementById(id).value = '');
```

In `openEditUserModal()` (`admin.html:687-702`), add after the existing
`document.getElementById('f-notes').value = u.notes || '';` line:

```javascript
  document.getElementById('f-exam-date').value      = u.exam_date || '';
  document.getElementById('f-referrer-unit').value  = u.referrer_unit || '';
  document.getElementById('f-referrer').value       = u.referrer || '';
  document.getElementById('f-referrer-phone').value = u.referrer_phone || '';
  document.getElementById('f-referrer-id').value    = u.referrer_id || '';
```

In `saveUser()` (`admin.html:704-771`), add after the existing
`const notes = document.getElementById('f-notes').value.trim();` line:

```javascript
  const examDate      = document.getElementById('f-exam-date').value;
  const referrerUnit  = document.getElementById('f-referrer-unit').value.trim();
  const referrer      = document.getElementById('f-referrer').value.trim();
  const referrerPhone = document.getElementById('f-referrer-phone').value.trim();
  const referrerId    = document.getElementById('f-referrer-id').value.trim();
```

and add these four keys into the `payload` object literal (`admin.html:748-758`):

```javascript
  const payload = {
    region: region || null,
    unit_name: unit || null,
    name,
    email: email || null,
    batch_name: batch || null,
    exam_date: examDate || null,
    referrer: referrer || null,
    referrer_phone: referrerPhone || null,
    referrer_unit: referrerUnit || null,
    referrer_id: referrerId || null,
    key_id: keyId,
    key_code: keyCode,
    expires_at: expiresAt || null,
    notes: notes || null
  };
```

- [ ] **Step 5: Update `renderTable()`'s search filter to include phone/referrer**

Replace the filter in `renderTable()` (`admin.html:511-518`):

```javascript
  const filtered = allStudents.filter(u =>
    u.name?.toLowerCase().includes(q) ||
    u.phone?.toLowerCase().includes(q) ||
    u.referrer?.toLowerCase().includes(q) ||
    u.referrer_unit?.toLowerCase().includes(q) ||
    u.region?.toLowerCase().includes(q) ||
    u.unit_name?.toLowerCase().includes(q) ||
    u.email?.toLowerCase().includes(q) ||
    u.batch_name?.toLowerCase().includes(q)
  );
```

- [ ] **Step 6: Manual verification**

Open `admin.html` in a browser, log in, go to 學員管理. Confirm the table shows
電話/考試日期/推薦人/推薦單位 columns, and that opening the edit modal on a
row created by `auto-register-student` (from Task 2's manual test) shows those
values pre-filled and saves correctly.

- [ ] **Step 7: Commit**

```bash
git add admin.html
git commit -m "feat(admin.html): show exam date and referrer fields for students"
```

---

## Task 7: `admin.html` — delete students and license keys

**Files:**
- Modify: `admin.html` (functions area, near `toggleUser`/`toggleKey`)

**Interfaces:**
- Produces: `deleteUser(id)` (referenced by Task 6 Step 2) and `deleteKey(id)`
  (wired into the keys table's 操作 column).

- [ ] **Step 1: Add `deleteUser`**

Insert immediately after `toggleUser()` (`admin.html:637-641`):

```javascript
async function deleteUser(id) {
  const u = allStudents.find(x => x.id === id);
  if (!u) return;
  if (!confirm('確定要刪除學員「' + u.name + '」嗎？此動作無法復原。')) return;

  if (u.key_id) {
    await sb.from('key_sessions').delete().eq('key_id', u.key_id);
  }
  const { error } = await sb.from('students').delete().eq('id', id);
  if (error) { alert('刪除失敗：' + error.message); return; }

  // Only the deleted student's own key: if no other student references it, remove it too.
  if (u.key_id) {
    const { data: others } = await sb.from('students').select('id').eq('key_id', u.key_id).limit(1);
    if (!others || others.length === 0) {
      await sb.from('license_keys').delete().eq('id', u.key_id);
    }
  }

  loadUsers();
  loadKeys();
}
```

- [ ] **Step 2: Add `deleteKey`**

Insert immediately after `toggleKey()` (`admin.html:911-915`):

```javascript
async function deleteKey(id) {
  const k = allKeys.find(x => x.id === id);
  if (!k) return;

  const { data: linked } = await sb.from('students').select('id').eq('key_id', id).limit(1);
  if (linked && linked.length > 0) {
    alert('此授權碼仍有學員使用中，請先刪除或改派該學員後再刪除授權碼。');
    return;
  }

  if (!confirm('確定要刪除授權碼「' + k.key_code + '」嗎？此動作無法復原。')) return;

  await sb.from('key_sessions').delete().eq('key_id', id);
  const { error } = await sb.from('license_keys').delete().eq('id', id);
  if (error) { alert('刪除失敗：' + error.message); return; }
  loadKeys();
}
```

- [ ] **Step 3: Wire the delete button into the keys table**

In `renderKeysTable()`, replace the 操作 cell template at `admin.html:831-837`:

```javascript
      <td>
        <button class="btn btn-outline btn-sm" onclick="openEditKeyModal('${k.id}')">編輯</button>
        ${k.is_active
          ? `<button class="btn btn-danger btn-sm" style="margin-left:4px" onclick="toggleKey('${k.id}',false)">停用</button>`
          : `<button class="btn btn-outline btn-sm" style="margin-left:4px" onclick="toggleKey('${k.id}',true)">啟用</button>`
        }
        <button class="btn btn-danger btn-sm" style="margin-left:4px" onclick="deleteKey('${k.id}')">刪除</button>
      </td>
```

(The student table's delete button was already wired in Task 6 Step 2.)

- [ ] **Step 4: Manual verification**

In the browser: create a throwaway student (via 新增學員, no key assigned) and
delete it — confirm dialog appears, row disappears, no console errors. Create a
throwaway license key and delete it. Try deleting a license key that's
currently assigned to a student — confirm the "仍有學員使用中" alert appears
and nothing is deleted.

- [ ] **Step 5: Commit**

```bash
git add admin.html
git commit -m "feat(admin.html): add student and license key deletion"
```

---

## Task 8: `admin.html` — extra statistics

**Files:**
- Modify: `admin.html:165-170` (stats cards markup), `admin.html:503-508` (`updateUserStats`)

**Interfaces:**
- Consumes: `allStudents` (already populated by `loadUsers()`).

- [ ] **Step 1: Add new stat cards to the markup**

Replace the stats row at `admin.html:165-170`:

```html
      <div class="stats" id="stats-row">
        <div class="stat-card"><div class="num" id="s-total">—</div><div class="lbl">總學員數</div></div>
        <div class="stat-card"><div class="num" id="s-today">—</div><div class="lbl">今日新增</div></div>
        <div class="stat-card"><div class="num" id="s-expiring">—</div><div class="lbl">即將過期（7天內）</div></div>
        <div class="stat-card"><div class="num" id="s-active">—</div><div class="lbl">已分配授權碼</div></div>
      </div>

      <div class="panel">
        <div class="panel-header"><h2>依推薦人／推薦單位統計</h2></div>
        <div style="overflow-x:auto">
          <table>
            <thead><tr><th>推薦人</th><th>推薦單位</th><th>學員數</th></tr></thead>
            <tbody id="referrer-stats-tbody"></tbody>
          </table>
        </div>
      </div>

      <div class="panel">
        <div class="panel-header"><h2>依考試日期統計</h2></div>
        <div style="overflow-x:auto">
          <table>
            <thead><tr><th>考試日期</th><th>學員數</th></tr></thead>
            <tbody id="examdate-stats-tbody"></tbody>
          </table>
        </div>
      </div>
```

(This drops the old `s-expired`/`s-logins` cards — "未分配授權碼" and "已寄送
郵件" are no longer central once auto-registration is the primary path; both
values are still derivable from the table itself if ever needed again.)

- [ ] **Step 2: Rewrite `updateUserStats()` and add the two grouping renderers**

Replace `updateUserStats()` (`admin.html:503-508`) with:

```javascript
function updateUserStats() {
  const now = new Date();
  const todayStr = now.toISOString().substring(0, 10);

  document.getElementById('s-total').textContent = allStudents.length;
  document.getElementById('s-today').textContent =
    allStudents.filter(s => (s.created_at || '').substring(0, 10) === todayStr).length;
  document.getElementById('s-expiring').textContent = allStudents.filter(s => {
    if (!s.expires_at) return false;
    const exp = new Date(s.expires_at);
    const daysLeft = Math.ceil((exp - now) / 86400000);
    return daysLeft >= 0 && daysLeft <= 7;
  }).length;
  document.getElementById('s-active').textContent = allStudents.filter(s => s.key_code).length;

  renderReferrerStats();
  renderExamDateStats();
}

function renderReferrerStats() {
  const groups = {};
  allStudents.forEach(s => {
    const key = (s.referrer || '（未填寫）') + '｜' + (s.referrer_unit || '（未填寫）');
    groups[key] = (groups[key] || 0) + 1;
  });

  const tbody = document.getElementById('referrer-stats-tbody');
  const entries = Object.entries(groups).sort((a, b) => b[1] - a[1]);
  if (!entries.length) {
    tbody.innerHTML = '<tr class="empty-row"><td colspan="3">尚無資料</td></tr>';
    return;
  }
  tbody.innerHTML = entries.map(([key, count]) => {
    const [referrer, unit] = key.split('｜');
    return `<tr><td>${esc(referrer)}</td><td>${esc(unit)}</td><td>${count}</td></tr>`;
  }).join('');
}

function renderExamDateStats() {
  const groups = {};
  allStudents.forEach(s => {
    const key = s.exam_date || '（未填寫）';
    groups[key] = (groups[key] || 0) + 1;
  });

  const tbody = document.getElementById('examdate-stats-tbody');
  const entries = Object.entries(groups).sort((a, b) => a[0].localeCompare(b[0]));
  if (!entries.length) {
    tbody.innerHTML = '<tr class="empty-row"><td colspan="2">尚無資料</td></tr>';
    return;
  }
  tbody.innerHTML = entries.map(([date, count]) =>
    `<tr><td>${esc(date)}</td><td>${count}</td></tr>`
  ).join('');
}
```

- [ ] **Step 3: Manual verification**

Reload `admin.html`, confirm the four stat cards render sensible numbers, and
that the two new grouping tables list every distinct referrer/unit and exam
date present in `allStudents` with correct counts (cross-check by eye against
the main student table).

- [ ] **Step 4: Commit**

```bash
git add admin.html
git commit -m "feat(admin.html): add today/expiring/referrer/exam-date stats"
```

---

## Task 9: Retire `register.html`

**Files:**
- Modify: `register.html` (full replacement)

- [ ] **Step 1: Replace the file with a redirect**

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="0; url=https://shinkong-insurance.github.io/insurance-exam-app/#/lk">
<title>學員報名 — 已移至新頁面</title>
</head>
<body>
<p>報名頁面已更新，正在為您導向新頁面…<br>
若未自動跳轉，請點此：
<a href="https://shinkong-insurance.github.io/insurance-exam-app/#/lk">https://shinkong-insurance.github.io/insurance-exam-app/#/lk</a>
</p>
<script>
location.replace('https://shinkong-insurance.github.io/insurance-exam-app/#/lk');
</script>
</body>
</html>
```

- [ ] **Step 2: Manual verification**

Open `register.html` directly in a browser and confirm it redirects to
`#/lk` and the new registration form loads there.

- [ ] **Step 3: Commit**

```bash
git add register.html
git commit -m "chore: retire register.html in favor of #/lk auto-registration"
```

---

## Self-Review Notes

- **Spec coverage:** every decision in the spec's §2 table maps to a task —
  auto-login (Task 4/5), field list (Task 5), exam-date source (Task 3),
  same-phone renewal (Task 2), legacy manual-key path untouched (no task
  modifies it), stats (Task 8), delete (Task 7), `register.html` retirement
  (Task 9).
- **Known gap flagged, not silently dropped:** Task 1 Step 2 and Task 2 Step 2
  both require a human to run an interactive command (`supabase login`, or
  pasting SQL into the Dashboard) — these cannot be completed by an
  unattended subagent and must be handed back to the user when reached.
- **Out of scope (per spec §9):** `_authGuard`'s default redirect to
  `/license`, the `/license` + `web_users` login path, and deleting the old
  `register-student` Edge Function are untouched by this plan.
