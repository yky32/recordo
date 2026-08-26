# Recordo 上架 · 共享最新停車場資訊

目標：用戶更新 App 後，**可以互相分享 / 看到最新場價**（唔係每人只得自己電話裡嘅資料）。

## 點樣達到

| 層 | 做咩 |
|----|------|
| **App Store binary** | compile 時打入 `SUPABASE_URL` + `SUPABASE_ANON_KEY` |
| **Supabase** | 公共 UGC DB（`price_reports` / `parks_ugc`） |
| **App 行為** | 開 app 拉 cloud；改價推 cloud；設定「同步最新場價」 |

本機永遠可離線用；有雲先「共享」。

---

## 上架前 checklist

### A. Supabase（你）
- [ ] Project Ready（`recordo-app`）
- [ ] SQL：跑 `supabase/SETUP_ALL.sql`（一次）
- [ ] Table Editor 見到 `price_reports`、`parks_ugc`
- [ ] 本機 `./scripts/run_recordo_supabase.sh` → 設定顯示 **已連**
- [ ] 機 A 改價 → 機 B 同步見到

### B. GitHub Secrets（TF / 正式包）
Repo → Settings → Secrets → Actions：

| Name | Value |
|------|--------|
| `SUPABASE_URL` | `https://jutuorafntyvukxzehlg.supabase.co` |
| `SUPABASE_ANON_KEY` | publishable / anon key |
| `SUPABASE_ACCESS_TOKEN` | Account → Access Tokens (`sbp_…`) — for Actions `db push` |
| `SUPABASE_DB_PASSWORD` | Project Settings → Database password |

Deploy workflow + Fastlane 會 `--dart-define` 入 IPA。  
**無 URL / ANON_KEY = 上架包永遠「本機 only」。**  
Schema：Actions → **Supabase** → Run workflow（`supabase db push`）。

### C. App Store Connect
- [ ] Privacy：說明收集 UGC 場價（自願提交）、無強制帳戶（而家 anon RLS）
- [ ] 截圖 / 描述可寫：司機互相更新香港停車場收費

### D. 驗收（TestFlight production-like）
- [ ] TF 安裝 → 設定「雲端 UGC = 已連」
- [ ] 改收費 snack：**已分享給其他 Recordo 用戶**
- [ ] 另一部機「同步最新場價」見到更新

---

## 用戶體感（上架後）

1. 開 app → 自動拉最新 shared 價  
2. 詳情改價 / 確認 → 寫本機 + 推雲  
3. 設定 → **同步最新場價** → 手動 refresh  
4. 更新 App 版本 → **同一 Supabase**，資料唔會因版本清空（OSM 在 bundle 可更新；UGC 在 cloud）

---

## 之後（非擋上架）
- Anonymous Auth + rate limit  
- 舉報垃圾價  
- 實付匿名聚合  

---

## 而家你要做
1. SQL `SETUP_ALL.sql`（若未跑）  
2. GitHub 加兩個 Secrets  
3. 回 `secrets done` → deploy TF 驗「已連」→ 再交審
