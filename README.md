# 去嘉義找 Joy（JoyGO-ChiaYi）

整合旅遊規劃、即時交通、天氣、地圖、社群與集章打卡的嘉義在地旅遊 App，使用 Flutter 開發。

> 2026S 行動裝置應用程式設計期末專題 · 第 13 組（邱采嫻、歐家怡）

## 製作動機

協助到訪嘉義的旅客在旅遊前做規劃，實際造訪時也能在同一個 App 中查看交通、天氣、地圖與嘉義最新資訊。

解決的痛點：

- **資訊分散**：旅遊、交通、天氣整合成單一入口
- **行程難規劃**：考量天氣、交通時間與路線的智慧排程
- **即時資訊不足**：公車動態、YouBike 可借/可還數量、天氣預報
- **特殊需求不易搜尋**：輪椅友善、寵物友善、哺集乳室等
- **多人共編與臨時應變**：共同編輯行程、AI 即時重排
- **缺乏探索動力**：集章、成就與足跡紀錄

## 主要功能

| 功能 | 說明 |
| --- | --- |
| 地圖探索 | 彩色分類圖釘 + 由近到遠列表，點擊顯示詳細資訊卡片 |
| 集章成就打卡 | GPS 進入景點 100m 內自動打卡（含冷卻時間）、連續天數、成就徽章、拍立得照片牆、白色遮罩逐步揭示的小地圖 |
| 社群貼文 | 行程貼文（可一鍵套用）與討論區，支援圖片、按讚、收藏、留言、檢舉 |
| 行程管理 | 自訂封面/圖示/日期、拖拉排序、智慧排序、行程地圖、記帳與分帳、旅伴群組、行事曆、倒數天數 |
| AI 行程助手 | 整合 Google Gemini：智慧排程、行程匯入修改、自由對話規劃 |
| 交通資訊 | TDX：公車、YouBike、台鐵、阿里山林鐵、高鐵 |
| 天氣資訊 | 中央氣象署 CWA 開放資料（嘉義市東區、阿里山鄉） |
| 活動/新聞 | 嘉義市政府開放資料 |
| 設定 | 繁中/英/日語言、15 種主題色、通知開關 |
| 管理者後台 | 資料統計、優惠券發送、權限管理、內容與舉報管理、JSON 匯入匯出、推播 |

## 系統架構

![系統架構](docs/images/architecture.png)

- **使用者端**：Flutter App（Provider 狀態管理）
- **後端**：Node.js Express（處理 TDX OAuth 2.0 Client Credentials，統一資料格式）
- **資料儲存**：Firebase Auth / Firestore / Storage
- **外部資料**：TDX、CWA、嘉義市政府開放資料、Google Gemini

![App 資料介接方式](docs/images/data-flow.jpg)

## 使用者端畫面

### 首頁、通知、交通、新聞

<table>
  <tr>
    <td align="center"><img src="docs/images/home.png" width="200"><br>首頁</td>
    <td align="center"><img src="docs/images/notifications.png" width="200"><br>通知中心</td>
    <td align="center"><img src="docs/images/transport.png" width="200"><br>交通動態</td>
    <td align="center"><img src="docs/images/news.png" width="200"><br>最新消息</td>
  </tr>
</table>

### 行程管理

<table>
  <tr>
    <td align="center"><img src="docs/images/trips.png" width="200"><br>我的行程</td>
    <td align="center"><img src="docs/images/favorites.png" width="200"><br>收藏景點</td>
    <td align="center"><img src="docs/images/calendar.png" width="200"><br>活動行事曆</td>
    <td align="center"><img src="docs/images/ai-planner.png" width="200"><br>AI 助手</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/create-trip.png" width="200"><br>建立行程</td>
    <td align="center"><img src="docs/images/trip-share.png" width="200"><br>旅行日報分享</td>
    <td align="center"><img src="docs/images/trip-edit.png" width="200"><br>行程編輯</td>
    <td align="center"><img src="docs/images/trip-map.png" width="200"><br>行程路線地圖</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/trip-candidates.png" width="200"><br>候選景點</td>
    <td align="center"><img src="docs/images/trip-expense.png" width="200"><br>旅遊分帳</td>
    <td></td>
    <td></td>
  </tr>
</table>

### 地圖探索

<table>
  <tr>
    <td align="center"><img src="docs/images/map.png" width="200"><br>圖釘標記</td>
    <td align="center"><img src="docs/images/map-list.png" width="200"><br>列表模式</td>
  </tr>
</table>

### 旅遊社群

<table>
  <tr>
    <td align="center"><img src="docs/images/community.png" width="200"><br>社群</td>
    <td align="center"><img src="docs/images/new-post.png" width="200"><br>發布貼文</td>
    <td align="center"><img src="docs/images/post-detail-1.png" width="200"><br>貼文內文（帳號 A）</td>
    <td align="center"><img src="docs/images/post-detail-2.png" width="200"><br>貼文內文（帳號 B）</td>
  </tr>
</table>

### 個人頁面與設定

<table>
  <tr>
    <td align="center"><img src="docs/images/profile.png" width="200"><br>個人頁面</td>
    <td align="center"><img src="docs/images/companions.png" width="200"><br>旅伴管理</td>
    <td align="center"><img src="docs/images/coupons.png" width="200"><br>優惠券</td>
    <td align="center"><img src="docs/images/saved-posts.png" width="200"><br>收藏貼文</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/settings.png" width="200"><br>設定</td>
    <td align="center"><img src="docs/images/login.png" width="200"><br>登入註冊</td>
    <td align="center"><img src="docs/images/weather.png" width="200"><br>天氣</td>
    <td></td>
  </tr>
</table>

### 集章成就

<table>
  <tr>
    <td align="center"><img src="docs/images/stamps-1.png" width="200"></td>
    <td align="center"><img src="docs/images/stamps-2.png" width="200"></td>
    <td align="center"><img src="docs/images/stamps-3.png" width="200"></td>
    <td align="center"><img src="docs/images/stamps-4.png" width="200"></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/stamps-5.png" width="200"></td>
    <td align="center"><img src="docs/images/stamps-6.png" width="200"></td>
    <td></td>
    <td></td>
  </tr>
</table>

集點印章、打卡照片牆、成就徽章、打卡排行榜、小地圖打卡紀錄。

## 管理者端畫面

<table>
  <tr>
    <td align="center"><img src="docs/images/admin-1.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-2.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-3.png" width="200"></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/admin-4.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-5.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-6.png" width="200"></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/admin-7.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-8.png" width="200"></td>
    <td align="center"><img src="docs/images/admin-9.png" width="200"></td>
  </tr>
</table>

資料統計與優惠券發送、使用者權限管理（升級管理者/停用帳號）、社群內容與舉報管理、JSON 資料匯入匯出、推播通知。

## 資料儲存

| 媒體類型 | 儲存位置 | 說明 |
| --- | --- | --- |
| 用戶大頭貼 | Firebase Storage | `avatars/{uid}.jpg`，URL 存入 Firestore `users` |
| 行程封面照片 | Firebase Storage | `trip_covers/{uid}/{tripId}.jpg` |
| 社群貼文圖片 | Firebase Storage | `posts/{uid}/{postId}/image_{n}.jpg` |
| 打卡照片 | 本地裝置 + Firebase Storage | 先存本地路徑，可選擇同步上傳 |
| 景點圖片 | 外部 CDN URL | 以 CachedNetworkImage 快取 |

資料 Schema（dbdiagram.io）：

![Schema 1](docs/images/schema-1.png)
![Schema 2](docs/images/schema-2.png)

## 技術重點

- Flutter 多套件整合（flutter_map、firebase_auth、cloud_firestore、firebase_storage、google_sign_in 等），以 Provider 管理語言/主題/字體大小與登入狀態
- Node.js Express 後端處理 TDX OAuth 2.0（取得、快取、刷新 Token），並將各種回傳格式標準化為統一 JSON
- 整合 Google Gemini API 進行 AI 行程規劃

## 資料來源

- [TDX 運輸資料流通服務](https://tdx.transportdata.tw/)
- [嘉義市政府開放資料](https://data.chiayi.gov.tw/opendata/)
- 中央氣象署 CWA 開放資料平台
- Google Gemini API

---

# 安裝與部署

## 專案架構

```
JoyGo-ChiaYi/                  ← Flutter App（主專案）
tdx-server/                    ← Spring Boot 後端伺服器
backup_or_upload_programs/     ← Firestore 資料備份 / 上傳工具
  export.js                      匯出 Firestore → 本機 + AWS S3
  restore.js                     從備份還原到 Firestore
  import_all_data.js             批次匯入景點靜態資料
  TDX_static_all.js              從 TDX API 拉取並寫入 Firestore
  uploadRestaurants.js           上傳餐廳資料
```

---

## 環境需求

| 工具 | 版本 |
|------|------|
| Flutter | 3.x 以上 |
| Dart | 3.0 以上 |
| Java | 17 以上 |
| Node.js | 18 以上 |
| Firebase CLI | 最新版 |
| AWS CLI | 2.x 以上 |

---

## 一、執行 Flutter App

### 1. 安裝套件

```powershell
cd JoyGo-ChiaYi
flutter pub get
```

### 2. 建立 local.env.json（API 金鑰設定）

複製範本並填入金鑰：

```powershell
copy local.env.json.example local.env.json
```

編輯 `local.env.json`：

```json
{
  "GEMINI_API_KEY": "你的 Gemini API Key",
  "AWS_ACCESS_KEY_ID": "你的 AWS Access Key",
  "AWS_SECRET_ACCESS_KEY": "你的 AWS Secret Key",
  "AWS_S3_BUCKET": "joygo-chiayi-backup",
  "AWS_S3_REGION": "ap-southeast-2"
}
```

> 此檔案已加入 .gitignore，不會提交到 Git。

### 3. 執行 App

```powershell
flutter run --dart-define-from-file=local.env.json
```

執行前請確認：
- Android 模擬器或實體裝置已連線
- tdx-server 伺服器已啟動（見第二節）

### 4. 建置 APK

```powershell
flutter build apk --dart-define-from-file=local.env.json
```

APK 位置：`build/app/outputs/flutter-apk/app-release.apk`

---

## 二、執行 tdx-server（Spring Boot 後端）

### 1. 設定環境變數

編輯 `tdx-server/.env`：

```
TDX_CLIENT_ID=你的 TDX Client ID
TDX_CLIENT_SECRET=你的 TDX Client Secret
CWA_API_KEY=你的中央氣象署 API Key
```

### 2. 啟動伺服器

```powershell
cd tdx-server
.\mvnw spring-boot:run
```

伺服器啟動後監聽 `http://localhost:8080`

### 3. API 端點一覽

| 方法 | 路徑 | 說明 |
|------|------|------|
| GET | `/api/transport/bus/{city}/{routeName}` | 公車到站預報 |
| GET | `/api/transport/bus/gps/{city}/{routeName}` | 公車即時位置 |
| GET | `/api/transport/bus/nearby` | 附近公車站 |
| GET | `/api/transport/tra/od` | 台鐵班次查詢 |
| GET | `/api/transport/tra/liveboard/{stationId}` | 台鐵即時動態 |
| GET | `/api/transport/thsr/od` | 高鐵班次查詢 |
| GET | `/api/transport/youbike` | YouBike 即時資料 |
| GET | `/api/transport/weather/{cityType}` | 天氣預報（Chiayi / ChiayiCounty） |

### 4. App 連線設定

| 環境 | 伺服器位址 |
|------|-----------|
| Android 模擬器 | `http://10.0.2.2:8080/api/transport` |
| 實機測試 | `http://{本機 IP}:8080/api/transport` |

---

## 三、Firebase Cloud Functions 部署

### 1. 安裝套件

```powershell
cd functions
npm install
```

### 2. 部署

```powershell
firebase deploy --only functions
```

目前部署的 Function：

| 函式名稱 | 觸發條件 | 功能 |
|---------|---------|------|
| `sendBroadcastNotification` | Firestore `broadcasts/{id}` 建立 | FCM 推播給所有用戶 |

---

## 四、資料備份（Firestore → AWS S3）

### 事前準備

1. 確認 `serviceAccountKey.json` 放在 `D:\chiayi_OuO\` 資料夾（Firebase Console → 專案設定 → 服務帳戶 → 產生新的私密金鑰）
2. 確認 `.env` 已填入 AWS 金鑰

### 安裝套件（第一次才需要）

```powershell
cd backup_or_upload_programs
npm install
```

### 備份全部資料

```powershell
cd backup_or_upload_programs
node export.js
```

備份完成後：
- 本機：`D:\chiayi_OuO\backups\backup-{時間戳記}\`
- AWS S3：`joygo-chiayi-backup/firestore-data/backup-{時間戳記}/`

### 備份單一集合

```powershell
node export.js --collection=restaurants
```

### 只存本機（不上傳 S3）

```powershell
node export.js --no-s3
```

### 從備份還原

```powershell
node restore.js --backup=../backups/backup-{時間戳記}
```

---

## 五、靜態資料上傳工具

### 從 TDX API 拉取景點並寫入 Firestore

```powershell
cd backup_or_upload_programs
node TDX_static_all.js
```

### 批次匯入所有靜態資料

```powershell
node import_all_data.js
```

### 上傳餐廳資料

```powershell
node uploadRestaurants.js
```

---

## 七、金鑰與設定管理

| 金鑰 | 位置 | 說明 |
|------|------|------|
| `GEMINI_API_KEY` | `local.env.json` | Gemini AI 行程規劃 / 翻譯 |
| `TDX_CLIENT_ID/SECRET` | `tdx-server/.env` | 交通部 TDX API |
| `CWA_API_KEY` | `tdx-server/.env` | 中央氣象署 API |
| `AWS_ACCESS_KEY_ID/SECRET` | `local.env.json` + `backup_or_upload_programs/.env` | AWS S3 備份 |
| `serviceAccountKey.json` | `D:\chiayi_OuO\`（不進 git） | Firebase Admin SDK |
| `google-services.json` | `android/app/` | Firebase Android 設定 |

> **安全規範**：以上所有金鑰檔案皆已加入 `.gitignore`，嚴禁提交到版本控制。

---

## 八、AWS S3 備份結構

```
joygo-chiayi-backup/
└── firestore-data/
    └── backup-{YYYY-MM-DDTHH-MM-SS}/
        ├── manifest.json          備份摘要（集合清單、筆數、S3 URL）
        ├── users.json
        ├── trips.json
        ├── community_posts.json
        ├── tdx_spots.json
        ├── restaurants.json
        └── ... （共 35 個集合）
```

---

## 九、常見問題

**Q：執行 App 時公車 / 天氣資料載入失敗**
A：確認 tdx-server 已啟動，實機測試請確認和電腦在同一 Wi-Fi 並使用正確的本機 IP。

**Q：AI 行程規劃無法使用**
A：確認 `local.env.json` 的 `GEMINI_API_KEY` 已填入，且以 `--dart-define-from-file` 啟動。

**Q：備份腳本找不到 serviceAccountKey.json**
A：至 Firebase Console → 專案設定 → 服務帳戶 → 產生新的私密金鑰，下載後放到 `D:\chiayi_OuO\`。

**Q：S3 上傳失敗**
A：確認 `backup_or_upload_programs/.env` 的 AWS 金鑰正確，並確認 IAM 使用者有 `AmazonS3FullAccess` 權限。
