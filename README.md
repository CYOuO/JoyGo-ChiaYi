# JoyGo 嘉義智慧旅遊 App

嘉義縣市智慧旅遊行動應用程式，整合景點、交通、社群、AI 行程規劃等功能。

---

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

## 六、App 功能頁面一覽

| 頁面 | 功能 |
|------|------|
| 首頁 | 天氣、快速入口、推薦景點 |
| 地圖 | 互動式地圖、景點標記、附近搜尋 |
| 搜尋 | 全站景點 / 餐廳 / 商店搜尋 |
| 行程 | 建立 / 編輯行程、AI 規劃、邀請同行者 |
| AI 規劃師 | Gemini 2.0 Flash 生成逐日行程建議 |
| 社群 | 發文、留言、按讚、追蹤 |
| 集章 | 打卡集章、成就排行榜 |
| 相機 | 拍照 / 掃 QR Code |
| 支出管理 | 行程花費分帳、QR Code 收款 |
| 交通 | 公車、台鐵、高鐵、阿里山森鐵、YouBike |
| 天氣 | 嘉義市 / 縣七日天氣預報 |
| 通知 | 社群互動、行程邀請通知 |
| 個人頁 | 編輯資料、收藏、追蹤、集章記錄 |
| 設定 | 語言、主題、推播開關 |
| 管理後台 | 景點管理、廣播推播、資料匯入匯出（管理員限定） |

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
