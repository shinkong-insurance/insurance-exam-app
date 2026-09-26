# `#/lk` 自動授權設計

- 日期：2026-09-14
- 範圍：`insurance-exam-app`（`gh-pages` branch，對應線上網站
  `https://shinkong-insurance.github.io/insurance-exam-app/#/lk`）

## 1. 背景

目前 `#/lk` 入口採「授權碼登入」：講師須先在後台（`admin.html`）手動或批量產生
`SK-YYYY-XXXX-NNNN` 授權碼，交給學員輸入才能進入題庫
（`lib/features/auth/lk_gate_page.dart` + `lib/core/services/lk_auth_service.dart`，
Supabase 表 `license_keys` / `key_sessions`）。

另有一支獨立的靜態頁 `register.html`，讓學員自行填寫姓名/信箱/手機/區部/單位/梯次/
介紹人姓名/介紹人手機並送出後，呼叫 Supabase Edge Function
`register-student`（原始碼未存在任何本機目錄，僅存在 Supabase 雲端）自動產生授權碼並
寄信通知。這支頁面**未接入** `#/lk` 的登入流程，也未強制填寫求全（沒有考試日期、沒有
推薦人單位/員編欄位）。

本設計要把「填表單即自動取得 60 天授權」直接做進 `#/lk` 入口，取代目前「先跟講師要碼」
的預設路徑，並補齊講師後台的管理、統計、刪除功能。

## 2. 決策摘要（已與使用者確認）

| 項目 | 決定 |
|---|---|
| 授權發放方式 | 送出表單後**直接自動登入**，不顯示/不寄送授權碼給學員 |
| 表單欄位 | 姓名、電話、考試日期（下拉，近 2 個月內任選）、推薦人姓名、推薦人電話、推薦人單位、推薦人員編（共 7 欄，皆為新表單欄位；`register.html` 原有的區部/單位/信箱欄位不沿用） |
| 考試日期來源 | 前端直接產生「近 2 個月」的日期下拉選項，不做後台可維護的日期清單 |
| 重複填寫（同電話） | 視為同一人；以電話號碼查找既有紀錄，效期從**本次送出時間**重新起算 60 天（等同自動續權），並直接建立新 session 登入 |
| 舊「手動/批量產生授權碼」機制 | 保留，作為講師的備用/特例發碼途徑，`admin.html` 對應功能不變動 |
| 講師後台統計需求 | 總學員數、今日新增、即將到期；按推薦人/推薦單位分組；按考試日期分組 |
| 講師後台刪除 | 學員與授權碼皆需可刪除（含確認），刪除學員需一併清除關聯的 `license_keys` / `key_sessions` |
| `register.html` | 直接停用，改為導頁到 `#/lk` |
| 實作方式 | 新寫一支 Edge Function（見下），不修改/沿用已遺失原始碼的舊 `register-student` function |

## 3. 資料模型變更（Supabase `students` 表）

依現有 `register.html` 送出的欄位推斷，`students` 表目前至少有：
`id, region, unit_name, name, email, phone, batch_name, referrer, referrer_phone,
key_id, key_code, expires_at, notes, is_active, email_sent_at, created_at`
（實作前需以 Supabase Dashboard 確認實際欄位型別與既有 NOT NULL/唯一限制）。

新增欄位：

- `exam_date date` — 學員選擇的考試日期
- `referrer_unit text` — 推薦人單位
- `referrer_id text` — 推薦人員編

`phone` 需要有唯一索引（或至少建立一般索引供查找），作為「同電話視為同一人」的查找鍵。
若目前 `phone` 欄位允許重複且無索引，需新增 `UNIQUE` constraint 或改用「先查後 upsert」
邏輯於 Edge Function 內以交易方式處理，避免競態下產生重複學員列。

`email`、`region`、`unit_name` 欄位保留在表結構中（相容既有資料/既有備用發碼路徑），但
新表單不再收集，新增紀錄時這些欄位存 `null`。

## 4. 新 Edge Function：`auto-register-student`

全新撰寫（非修改舊 `register-student`），使用 service-role key（僅存在伺服器端，不透過
前端 anon key 觸碰資料表），部署於同一 Supabase 專案（`kbclpucolchpwykqciyw`）。

**輸入**（JSON body）：
```
{ name, phone, exam_date, referrer_name, referrer_phone, referrer_unit, referrer_id }
```
`name`、`phone`、`exam_date` 為必填；其餘介紹人欄位選填。

**邏輯**：
1. 基本驗證（姓名非空、電話格式、exam_date 為合法日期字串）。
2. 以 `phone` 查詢 `students` 是否已有紀錄。
3. **不存在**：
   - 產生新 `key_code`（沿用現有 `SK-YYYY-XXXX-NNNN` 格式邏輯）。
   - 於 `license_keys` insert 一筆（`batch_name` 標記為如 `AUTO`，`max_uses = 0`（不限
     裝置數，因為裝置層級限制已無意義——同一人以電話號碼識別，重複填表即視為續權而非
     多開帳號），`expires_at` = 今天 + 60 天，`is_active = true`）。
   - 於 `students` insert 一筆，寫入表單欄位 + 對應 `key_id`/`key_code`/`expires_at`。
4. **已存在（同電話）**：
   - 更新該學員列的 `exam_date/referrer_*` 欄位為本次填寫內容。
   - 將對應 `license_keys.expires_at` 與 `students.expires_at` 都重新設為
     今天 + 60 天，並確保 `is_active = true`（重新填表視為續權，即使先前被停用）。
5. 回傳：`{ key_id, key_code, expires_at }`（不需要回傳給學員看，Flutter 端直接拿來
   建立 session，UI 上不顯示授權碼文字）。
6. 錯誤時回傳 `{ error: "訊息" }` 並用適當 HTTP status。

**安全性**：這支 function 本質上是一個無驗證的公開自助端點（任何人都能呼叫），與現有
`register-student` 風險等級相同（現況已是如此）。不在本次範圍內額外加驗證碼/防灌水機制
（使用者未提出此需求），但建議在 function 內對單一電話號碼加基本頻率限制（例如同電話
60 秒內只處理一次請求），避免誤觸雙擊送出造成的重複請求問題；這屬於實作細節，非設計變更
重點。

## 5. Flutter `/lk` 頁面（`lib/features/auth/lk_gate_page.dart`）

改為雙模式：

- **預設畫面**：自動註冊表單 — 姓名、電話、考試日期（`DropdownButton`，選項為
  今天起算未來 2 個月內的日期，前端 `DateTime` 計算產生，不需要打 API）、推薦人姓名、
  推薦人電話、推薦人單位、推薦人員編。送出按鈕文案如「送出並開始學習」。
- **備用連結**：畫面下方一個文字連結「使用授權碼登入」，點擊後切換顯示原本的授權碼輸入
  欄位＋「驗證授權碼並進入」按鈕（沿用現有 `_login()` 邏輯，不變動）。
- 送出自動註冊表單成功後，行為對齊現有 `_login()` 成功分支：呼叫
  `StudyLogger.login(keyCode)`、`context.go('/')`。

## 6. `LkAuthService` 新方法

新增 `static Future<LkLoginResponse> autoRegister({name, phone, examDate, referrerName,
referrerPhone, referrerUnit, referrerId})`：

- 呼叫 `auto-register-student` Edge Function。
- 成功時比照現有 `login()` 尾段，把回傳的 `key_id/key_code/expires_at` 寫入
  `SharedPreferences`（沿用同一組 `_kLk*` key），回傳 `LkLoginResult.success`。
- 失敗時回傳 `LkLoginResult.error` 並帶錯誤訊息。
- 不需要走 `_upsertSession`/`key_sessions` 裝置名額邏輯：因 `max_uses = 0`（見第 4
  節），裝置層級的使用次數限制對自動註冊的授權碼不適用，`autoRegister()` 不寫入
  `key_sessions`。`key_sessions` 僅繼續服務既有「備用授權碼登入」路徑（`_login()`，
  不變動）。

## 7. `admin.html` 後台變更

### 7.1 新增欄位顯示
「學員管理」表格新增三欄：考試日期、推薦人單位、推薦人員編（`u.exam_date`,
`u.referrer_unit`, `u.referrer_id`），新增/編輯學員 Modal 同步加上對應輸入框。

### 7.2 刪除功能
- 學員列與授權碼列的「操作」欄各加一個「刪除」按鈕（`btn-danger`），點擊先 `confirm()`
  對話框二次確認。
- 刪除學員（`deleteUser(id)`）：需先刪除該學員對應 `key_id` 在 `key_sessions` 的紀錄，
  再刪除 `license_keys` 對應列（若該授權碼未被其他學員共用），最後刪除 `students` 列；
  或視資料庫是否已設定 `ON DELETE CASCADE` 外鍵而簡化（實作前需查證 schema）。
- 刪除授權碼（`deleteKey(id)`）：同樣需先處理 `key_sessions` 關聯列，並防呆——若該
  授權碼仍被某學員 `key_id` 引用，需提示「請先刪除或改派對應學員」而非直接刪除造成
  孤兒外鍵。

### 7.3 新增統計
在既有 `updateUserStats()` 基礎上擴充：
- 今日新增：`allStudents.filter(s => s.created_at 是今天)`。
- 即將到期：沿用現有「剩餘天數 ≤ 7」邏輯做總數統計卡片。
- 按推薦人／推薦單位分組：以 `referrer`（推薦人姓名）或 `referrer_unit` 做
  `reduce` 分組計數，呈現為表格或條列（不需要另外向後端查詢，直接用已載入的
  `allStudents` 前端聚合，資料量可負擔）。
- 按考試日期分組：以 `exam_date` 分組計數，呈現方式同上。

「授權碼管理」分頁的既有統計/批量產生功能不變動。

## 8. `register.html`

整支頁面內容清空，改為單純的重導頁（`<meta http-equiv="refresh">` 或
`location.replace('...#/lk')`）指到 `https://shinkong-insurance.github.io/insurance-exam-app/#/lk`，
避免兩套註冊入口並存造成欄位/資料不一致。原本連到 `register.html` 的外部連結
（如講師發送的招生連結）仍可繼續使用，只是會被導去新的 `#/lk` 自動註冊表單。

## 9. 範圍外（本次不處理）

- `router.dart` 中 `_authGuard` 對未登入使用者的預設導頁目標是 `/license`
  （身分證登入）而非 `/lk`，這是既有行為，非本次功能要求，不予變動。
- `/license`、`web_users` 表、Flutter 內建 `/admin`（`admin_dashboard_page.dart`）
  屬於另一套「身分證登入」機制，與本次 `/lk` 自動授權無關，不予變動。
- 舊 Edge Function `register-student` 與 `register.html` 停用後即無使用者，不刪除
  （避免影響任何仍在使用中的外部連結／既有資料），僅停止呼叫。

## 10. 測試計畫

- Flutter：新增/擴充 `lk_gate_page` 與 `lk_auth_service` 的 widget/unit test，覆蓋
  自動註冊表單提交成功、Edge Function 回錯、切換至授權碼備用登入等路徑。
- Edge Function：以 `curl`/測試腳本打 `auto-register-student`，覆蓋「新電話」「重複
  電話續權」「缺必填欄位」情境，確認 `expires_at` 計算與 upsert 行為正確。
- `admin.html`：手動於瀏覽器驗證新欄位顯示、刪除確認流程、統計數字正確性（可用瀏覽器
  自動化工具比對畫面呈現的數字與資料庫實際筆數）。
- 部署後於正式站 `#/lk` 走一次完整自動註冊流程，確認登入後可正常進入題庫、`admin.html`
  能看到該筆新資料。

## 11. 部署備註

`auto-register-student` 需要以 Supabase CLI（`supabase functions deploy`）或 Dashboard
部署到專案 `kbclpucolchpwykqciyw`；本機/repo 內沒有 `supabase/functions/` 目錄，需要在
實作計畫中包含「初始化 `supabase/functions/auto-register-student/index.ts` 並部署」的步驟，
且需要有效的 Supabase 專案存取權限（CLI 登入或 Dashboard 帳號）才能完成部署與確認新增的
`students` 欄位／索引。
