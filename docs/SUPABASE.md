# Recordo × Supabase · Common DB 教學 + 計劃

目標：**全港場庫喺 cloud**。App 開一次就 dump 落本機玩；之後只喺 `catalog_meta.version` 新過本機先再 dump。

---

## 架構（記低）

```
┌─────────────────────────────────────────────┐
│  Recordo app                                │
│  · 本機 catalog snapshot（離線玩）            │
│  · OSM json = 第一次 / 無網後備               │
│  · SharedPreferences（自己改價、報新場 overlay）│
│  · 開 app：讀本機 → GET version → 有更新先 dump │
└──────────────────┬──────────────────────────┘
                   │ anon key + RLS
                   ▼
┌─────────────────────────────────────────────┐
│  Supabase Postgres                          │
│  parks            全港場庫（OSM+seed+UGC+價）  │
│  catalog_meta     version / park_count       │
│  catalog_dump()   一次過 jsonb dump           │
│  parks_ugc        用戶報新場（trigger → parks）│
│  price_reports    改價（trigger 寫回 parks）   │
│  park_prices      view = 中位價               │
└─────────────────────────────────────────────┘
```

| 數據 | 放邊 |
|------|------|
| **全港場庫** | Cloud `parks` → 本機 `catalog/parks_v1.json` |
| OSM 後備 | App `assets/data/hk_osm_parks.json`（未 dump 或無網） |
| Seed 示範價 | seed script 寫入 `parks` |
| **共享場價 + 備註** | `price_reports` → 寫入 `parks` + version++ |
| **共享新場** | `parks_ugc` → `parks` + version++ |
| 你自己嘅計時 / 實付 history | **本機** |

原則：**永遠先用本機 snapshot 開地圖**；version 無變就 0 download。改價仍然先寫本機再推雲。

---

## 你要做嘅設定（一次）

### Step 1 — 開 project
1. 開 https://supabase.com → 登入  
2. **New project**  
   - Name: `recordo`（任意）  
   - Region: **Southeast Asia (Singapore)** 較近 HK  
   - Database password: 自己存低（CLI 用）  
3. 等 project 變綠色 Ready  

### Step 2 — 跑 SQL（建表）
1. 左欄 **SQL** → **New query**  
2. 貼上 repo 入面成份檔內容，**分兩次 Run**：  
   - 先：`supabase/migrations/20260324000000_recordo_ugc.sql`  
   - 再：`supabase/migrations/20260825000000_price_note.sql`  
3. 成功會見到 Success  

驗證：
```sql
select * from park_prices limit 5;
select * from parks_ugc limit 5;
```

### Step 3 — 抄 API keys
1. **Project Settings**（齒輪）→ **API**  
2. 抄：  
   - **Project URL** → `https://xxxxx.supabase.co`  
   - **anon public** key（長 `eyJ...`）  
3. **唔好**抄 `service_role` 入 app（呢把可以 bypass RLS）

### Step 4 — 本機 run 連 cloud
```bash
cd ~/Documents/git/personal/recordo

flutter run \
  --dart-define=SUPABASE_URL='https://YOUR_REF.supabase.co' \
  --dart-define=SUPABASE_ANON_KEY='eyJhbGciOi...'
```

設定頁 **關於 → 雲端 UGC** 應顯示：**Supabase 已連**

### Step 5 — 驗證兩邊同步
**機 A（有 define）**  
1. 入某場詳情 → 改收費 + 備註 → 提交  
2. Supabase → **Table Editor** → `price_reports` 應多一行  

**機 B / 刪 app 重裝（同樣 define）**  
1. 開 app → 同一場 → 應見到 cloud 價 / 備註  

---

## VS Code / Cursor 一鍵 run（可選）

建 `.vscode/launch.json`（已 gitignore 可放 secret；或用本機 only）：

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "recordo + supabase",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "toolArgs": [
        "--dart-define=SUPABASE_URL=https://YOUR.supabase.co",
        "--dart-define=SUPABASE_ANON_KEY=eyJ..."
      ]
    }
  ]
}
```

---

## TestFlight / CI（之後）

TF binary 要 **compile-time** 打入 define，否則 Production 永遠「本機 only」。

GitHub repo **Settings → Secrets and variables → Actions** 加：

| Secret | 值 |
|--------|-----|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | anon key |

Fastlane / `flutter build ipa` 要帶：
```
--dart-define=SUPABASE_URL=$SUPABASE_URL
--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```
（呢 PR 可加 CI wiring；你 secrets 就位後講一聲。）

---

## App 入面點用（已 code）

| 動作 | 本地 | Cloud |
|------|------|--------|
| 改收費 / 備註 | `ugcPrices` prefs | `price_reports` insert → parks + version++ |
| 確認價錢仍然啱 | confirms++ | insert `confirm_only` |
| 報告新場 | `ugcNewParks` | `parks_ugc` upsert → parks + version++ |
| App 啟動 | 讀本機 snapshot | `catalog_meta.version`；新先 `catalog_dump()` |

Settings：**雲端 UGC** = 有冇 initialize 成功。

---

## 計劃（分階段）

### ✅ Phase 0 — 而家（code 已有 + 呢份 doc）
- Schema + RLS anon read/insert  
- Offline-first repository  
- price_note column + remote wire  

### 🔲 Phase 1 — 你完成 portal（今日可做）
1. Create project + run 2 SQL  
2. `flutter run` + dart-define  
3. 兩部機 / 重裝 dogfood  

### 🔲 Phase 2 — Product polish
- 設定頁「同步 UGC」手動 refresh  
- 提交成功 snack：本機 only vs 已上雲  
- List 顯示「雲端更新」小標  

### 🔲 Phase 3 — Trust / 防 spam
- Anonymous Auth（每 user 一個 id）  
- Edge Function rate limit  
- 舉報 / 隱藏異常價  

### 🔲 Phase 4 — 可選
- 實付 history 匿名上報（平均實付）  
- Admin dashboard  
- Realtime subscribe `price_reports`  

**刻意唔放：** vacancy live API、service_role 入 client。OSM 而家 seed 入 `parks`；app bundle 只係後備。

Seed（GHA 喺 `db push` 之後跑）：
```bash
python3 scripts/seed_parks_catalog.py
# needs SUPABASE_ACCESS_TOKEN + SUPABASE_URL
```

---

## 常見問題

**Q: 無 define 會點？**  
A: App 正常用，全本機。Settings 顯示「本機 only」。

**Q: RLS 係咪好危險（人人可 insert）？**  
A: 冷啟動 OK；有 traffic 要 Phase 3。Anon insert 有簡單 hourly 範圍 check。

**Q: park_id 點對？**  
A: 用 app 內部 id（`osm:way/…` / seed / `ugc-…`），兩邊一致。

**Q: 可唔可以 GUI 改數據？**  
A: Supabase **Table Editor** 可以，方便 debug。

---

## 你完成 Step 1–3 後

回我：
```
SUPABASE ready
URL: https://xxxx.supabase.co
```
（**唔好** paste anon key 入 chat；本機自己 keep）

然後我可以：
1. 幫你 check CI dart-define wiring  
2. 加「同步」掣 + 上雲 snack  
3. merge + TF（有 secrets）
