# 我的單字冒險島 2.0 — 真正好友／雲端版

這個版本以原本單字冒險島 HTML 為基礎，加入 Supabase 帳號驗證、雲端學習資料、個人邀請碼、好友關係、好友 XP 排行榜。沒有填入你的雲端金鑰，因此需要你建立自己的 Supabase 專案後才能啟用多人功能；未設定時仍可本機練習。

## 使用的服務
- **Supabase Auth**：電子郵件／密碼註冊與登入。
- **Supabase PostgreSQL**：玩家個人資料、邀請碼、好友關係、XP 事件與學習資料。
- **Vercel**（或任何靜態網站主機）：發布網站。

## 部署步驟

### 1. 建立 Supabase 專案
1. 到 https://supabase.com/ 建立免費專案，記下資料庫密碼並選擇靠近玩家的區域。
2. 打開專案的 **SQL Editor**，建立 New query。
3. 將 `supabase_schema.sql` 全文貼入並執行。
4. 到 **Project Settings → API**（或 API Keys），複製 Project URL 和 `anon` / publishable key。**絕對不要把 `service_role` 或 secret key 放進前端。**

### 2. 設定前端
1. 用文字編輯器開啟 `config.js`。
2. 將 `SUPABASE_URL` 改成你的 Project URL，將 `SUPABASE_ANON_KEY` 改成公開 anon/publishable key。
3. 儲存。這兩項本來就會出現在瀏覽器，資料安全依靠 SQL 的 Row Level Security (RLS)，不是靠隱藏 anon key。

### 3. 開啟 Email 驗證設定
1. 在 Supabase **Authentication → URL Configuration**，設定網站 URL（本機測試可先用 `http://localhost:8000`，部署後改成你的正式網址）。
2. 在 Authentication → Providers → Email，決定是否要求 Email confirmation。若開啟，使用者註冊後要先點驗證信，再回網站登入。
3. 將正式網站網域加入 Redirect URLs。

### 4. 本機測試
在 `vocab_island_cloud` 資料夾開啟終端機執行：

```bash
python3 -m http.server 8000
```

瀏覽 `http://localhost:8000`。請不要直接用 `file://` 開啟，因為登入跳轉和瀏覽器安全政策可能造成問題。

### 5. 部署到 Vercel
1. 將整個資料夾上傳到自己的 GitHub repository。
2. 在 https://vercel.com/ 匯入 repository，Framework Preset 選 **Other**，Build Command 留空，Output Directory 設為 `.`。
3. 部署後，把 Vercel 網址加入 Supabase Auth 的 Site URL 和 Redirect URLs。
4. 如果修改了 `config.js`，重新部署。

## 如何測試好友邀請碼
1. 使用兩個不同 Email 註冊兩個帳號（可用兩個瀏覽器或一個無痕視窗）。
2. 在「好友排行榜」查看第一個帳號的邀請碼並複製。
3. 切換到第二個帳號，在「朋友的邀請碼」欄位貼上，按「加入」。
4. 兩邊都會出現對方；答對題目後 XP 由資料庫 RPC 更新，重新整理排行榜即可查看分數。

## 資料與安全說明
- 使用者的單字、歷史紀錄等學習資料存在 `user_data`，僅該帳號可讀寫。
- 玩家 XP 不接受前端直接更新；透過 `award_xp` RPC，限制每次獎勵值及每日 XP 上限，並用事件 UUID 防止同一事件重複計分。
- 這是適合個人／小型專案的基礎保護，不是防作弊的商業競技系統。熟悉開發者工具的人仍可能呼叫公開 RPC 假造答題事件；若要高強度防作弊，應把題目出題、答題驗證、速率限制移到 Edge Function／伺服器端。
- 目前好友加入是直接互加，不是「送出邀請、等待接受」的雙向邀請流程。
- 匯入舊版本機資料：先在舊版匯出 JSON 備份；新版登入後可匯入單字 JSON，之後按「☁️ 立即同步」。本機舊 XP 不會覆寫雲端權威 XP。
- 本專案不會替你建立 Supabase 專案、代填金鑰或代替你點選部署；這些步驟必須由你在自己的帳號中完成。

## 重要
這是純前端靜態網站加 Supabase 雲端後端。**不要把 Supabase service_role key 放進 `config.js`、HTML、GitHub 或任何瀏覽器程式碼。**
