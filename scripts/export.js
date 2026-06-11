/**
 * 腳本 2：備份匯出 (Export) — 支援本地 + AWS S3
 *
 * 用途：將 Firestore 指定 Collection（或全部）匯出為 JSON 並上傳至 S3
 * 執行：
 *   node scripts/export.js                        # 匯出所有 Collection
 *   node scripts/export.js --collection=products  # 只匯出 products
 *   node scripts/export.js --out=./my-backup      # 指定本地輸出目錄
 *   node scripts/export.js --no-local             # 不保留本地檔案（僅上傳 S3）
 *
 * 環境變數（.env 或系統環境）：
 *   AWS_REGION         — S3 bucket 所在區域（預設 ap-southeast-2）
 *   AWS_S3_BUCKET      — S3 bucket 名稱
 *   AWS_ACCESS_KEY_ID  — AWS 存取金鑰（若使用 IAM Role 可省略）
 *   AWS_SECRET_ACCESS_KEY
 */

require('dotenv').config();
const admin = require('firebase-admin');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const fs   = require('fs');
const path = require('path');

// ─── 設定 ───────────────────────────────────────
const SERVICE_ACCOUNT_PATH = path.resolve(__dirname, '../serviceAccountKey.json');
const DEFAULT_OUTPUT_DIR   = path.resolve(__dirname, '../backups');

const S3_BUCKET = process.env.AWS_S3_BUCKET;
const S3_REGION = process.env.AWS_REGION || 'ap-southeast-2';
// ────────────────────────────────────────────────

if (!S3_BUCKET) {
  console.error('❌ 缺少環境變數：AWS_S3_BUCKET');
  console.error('   請在 .env 或系統環境中設定 AWS_S3_BUCKET');
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  });
}
const db = admin.firestore();

const s3 = new S3Client({ region: S3_REGION });

function parseArgs() {
  const args = {};
  process.argv.slice(2).forEach(arg => {
    const [key, value] = arg.replace('--', '').split('=');
    args[key] = value ?? true;
  });
  return args;
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

async function exportCollection(collectionRef, depth = 0) {
  const snapshot = await collectionRef.get();
  const records  = [];

  for (const doc of snapshot.docs) {
    const entry = { id: doc.id, data: doc.data() };

    const subCollections = await doc.ref.listCollections();
    if (subCollections.length > 0) {
      entry.subCollections = {};
      for (const subCol of subCollections) {
        const indent = '  '.repeat(depth + 2);
        process.stdout.write(`${indent}📂 子集合: ${subCol.id} ...`);
        entry.subCollections[subCol.id] = await exportCollection(subCol, depth + 1);
        process.stdout.write(` (${entry.subCollections[subCol.id].length} 筆)\n`);
      }
    }

    records.push(entry);
  }

  return records;
}

async function listCollections() {
  const cols = await db.listCollections();
  return cols.map(c => c.id);
}

/** 上傳單一 Buffer / 字串至 S3 */
async function uploadToS3(s3Key, body, contentType = 'application/json') {
  await s3.send(new PutObjectCommand({
    Bucket:      S3_BUCKET,
    Key:         s3Key,
    Body:        body,
    ContentType: contentType,
  }));
}

async function main() {
  const args      = parseArgs();
  const targetCol = args.collection || null;
  const outputDir = path.resolve(args.out || DEFAULT_OUTPUT_DIR);
  const keepLocal = !args['no-local'];
  const ts        = timestamp();
  const backupDir = path.join(outputDir, `backup-${ts}`);
  const s3Prefix  = `firestore-backups/backup-${ts}`;

  if (keepLocal) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  console.log(`\n💾 Firebase Export → AWS S3`);
  console.log(`   目標        : ${targetCol || '全部 Collection'}`);
  console.log(`   S3 Bucket   : ${S3_BUCKET}`);
  console.log(`   S3 前綴     : ${s3Prefix}/`);
  if (keepLocal) {
    console.log(`   本地備份    : ${backupDir}`);
  }
  console.log('');

  const t0 = Date.now();

  let collections;
  if (targetCol) {
    collections = [targetCol];
  } else {
    collections = await listCollections();
    console.log(`📋 發現 ${collections.length} 個 Collection: ${collections.join(', ')}\n`);
  }

  const manifest = {
    exportedAt  : new Date().toISOString(),
    s3Bucket    : S3_BUCKET,
    s3Prefix    : s3Prefix,
    collections : {},
  };

  for (const colName of collections) {
    process.stdout.write(`📤 匯出 ${colName} ...`);

    const records = await exportCollection(db.collection(colName));
    const json    = JSON.stringify(records, null, 2);
    const s3Key   = `${s3Prefix}/${colName}.json`;

    // 上傳至 S3
    await uploadToS3(s3Key, json);

    // 選擇性保留本地副本
    if (keepLocal) {
      fs.writeFileSync(path.join(backupDir, `${colName}.json`), json, 'utf8');
    }

    manifest.collections[colName] = {
      count  : records.length,
      s3Key  : s3Key,
      file   : `${colName}.json`,
    };

    process.stdout.write(` ✅ ${records.length} 筆 → s3://${S3_BUCKET}/${s3Key}\n`);
  }

  // 上傳 manifest
  const manifestJson = JSON.stringify(manifest, null, 2);
  const manifestKey  = `${s3Prefix}/manifest.json`;
  await uploadToS3(manifestKey, manifestJson);

  if (keepLocal) {
    fs.writeFileSync(path.join(backupDir, 'manifest.json'), manifestJson, 'utf8');
  }

  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  const total   = Object.values(manifest.collections).reduce((s, c) => s + c.count, 0);

  console.log(`\n✅ 匯出完成！`);
  console.log(`   共 ${collections.length} 個 Collection，${total} 筆資料`);
  console.log(`   耗時: ${elapsed}s`);
  console.log(`   S3 位置: s3://${S3_BUCKET}/${s3Prefix}/`);
  console.log(`   摘要檔案: s3://${S3_BUCKET}/${manifestKey}\n`);

  process.exit(0);
}

main().catch(err => {
  console.error(`\n❌ 匯出失敗: ${err.message}`);
  process.exit(1);
});
