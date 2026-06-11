/**
 * JoyGo 嘉義 — Firestore 資料備份腳本
 * 用法：node backup_firestore.js
 * 需求：npm install firebase-admin @aws-sdk/client-s3
 */

const admin  = require("firebase-admin");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const fs     = require("fs");
const path   = require("path");

// ── 設定 ──────────────────────────────────────────────
const BUCKET_NAME    = "joygo-chiayi-backup";
const REGION         = "ap-southeast-2";
const SERVICE_ACCOUNT = path.join(__dirname, "service-account.json");

// 要備份的集合
const COLLECTIONS = [
  "users",
  "trips",
  "community_posts",
  "tdx_spots",
  "restaurants",
  "good_shops",
  "pet_friendly_shops",
  "excellent_drink_shops",
  "tdx_alishan_rail_schedules",
  "broadcasts",
  "coupons",
  "leaderboard",
  "admin_users",
  "reports",
];
// ─────────────────────────────────────────────────────

async function backupCollection(db, colName) {
  const snapshot = await db.collection(colName).get();
  const docs = {};
  snapshot.forEach(doc => {
    docs[doc.id] = doc.data();
  });
  console.log(`  ${colName}: ${snapshot.size} 筆`);
  return docs;
}

async function main() {
  console.log("=== JoyGo Firestore 備份 ===");

  // 初始化 Firebase Admin
  if (!fs.existsSync(SERVICE_ACCOUNT)) {
    console.error("❌ 找不到 service-account.json，請先下載 Firebase 服務帳號金鑰");
    console.error("   Firebase Console → 專案設定 → 服務帳戶 → 產生新的私密金鑰");
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT)),
  });
  const db = admin.firestore();

  // 備份所有集合
  console.log("讀取 Firestore 資料...");
  const backup = { exportedAt: new Date().toISOString(), collections: {} };

  for (const col of COLLECTIONS) {
    try {
      backup.collections[col] = await backupCollection(db, col);
    } catch (e) {
      console.warn(`  ⚠️  ${col} 讀取失敗：${e.message}`);
    }
  }

  // 產生 JSON 檔案
  const date     = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const fileName = `firestore-backup-${date}.json`;
  const json     = JSON.stringify(backup, null, 2);

  console.log(`\n上傳至 S3 (${fileName})...`);

  // 上傳到 S3
  const s3 = new S3Client({ region: REGION });
  await s3.send(new PutObjectCommand({
    Bucket:      BUCKET_NAME,
    Key:         `firestore-data/${fileName}`,
    Body:        json,
    ContentType: "application/json",
    ACL:         "public-read",
  }));

  console.log("✅ 上傳成功！");
  console.log(`公開網址：https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/firestore-data/${fileName}`);

  process.exit(0);
}

main().catch(err => {
  console.error("❌ 錯誤：", err.message);
  process.exit(1);
});
