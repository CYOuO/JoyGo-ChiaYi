/**
 * 腳本 3：完整重建 (Restore) — 支援從 AWS S3 或本地備份還原
 *
 * 用途：從 S3 備份（或本地目錄）將資料還原回 Firestore
 * 支援「清空後重建」與「直接覆蓋還原」兩種模式
 *
 * 執行（S3 來源）：
 *   node scripts/restore.js --s3-prefix=firestore-backups/backup-2024-01-01T12-00-00
 *   node scripts/restore.js --s3-prefix=firestore-backups/backup-2024-01-01T12-00-00 --collection=products
 *   node scripts/restore.js --s3-prefix=firestore-backups/backup-2024-01-01T12-00-00 --wipe
 *
 * 執行（本地來源，與舊版相容）：
 *   node scripts/restore.js --backup=./backups/backup-2024-01-01T12-00-00
 *   node scripts/restore.js --backup=./backups/backup-2024-01-01T12-00-00 --wipe
 *
 * ⚠️  --wipe 模式會永久刪除現有資料，請謹慎使用！
 *
 * 環境變數：
 *   AWS_REGION         — S3 所在區域（預設 ap-southeast-2）
 *   AWS_S3_BUCKET      — S3 bucket 名稱
 *   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
 */

require('dotenv').config();
const admin    = require('firebase-admin');
const { S3Client, GetObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const fs       = require('fs');
const path     = require('path');
const readline = require('readline');

// ─── 設定 ───────────────────────────────────────
const SERVICE_ACCOUNT_PATH = path.resolve(__dirname, '../serviceAccountKey.json');
const BATCH_SIZE = 400;
const S3_BUCKET  = process.env.AWS_S3_BUCKET;
const S3_REGION  = process.env.AWS_REGION || 'ap-southeast-2';
// ────────────────────────────────────────────────

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

function confirm(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => {
    rl.question(`${question} (yes/NO): `, answer => {
      rl.close();
      resolve(answer.trim().toLowerCase() === 'yes');
    });
  });
}

/** 從 S3 取得物件內容並解析為 JSON */
async function getS3Json(s3Key) {
  const res    = await s3.send(new GetObjectCommand({ Bucket: S3_BUCKET, Key: s3Key }));
  const chunks = [];
  for await (const chunk of res.Body) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function wipeCollection(collectionRef) {
  const snapshot = await collectionRef.limit(400).get();
  if (snapshot.empty) return 0;

  let deleted = 0;
  const batch = db.batch();

  for (const doc of snapshot.docs) {
    const subCols = await doc.ref.listCollections();
    for (const subCol of subCols) {
      deleted += await wipeCollection(subCol);
    }
    batch.delete(doc.ref);
    deleted++;
  }

  await batch.commit();

  if (snapshot.size === 400) {
    deleted += await wipeCollection(collectionRef);
  }

  return deleted;
}

async function restoreRecords(collectionRef, records) {
  let written = 0;

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const chunk = records.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const record of chunk) {
      const ref = collectionRef.doc(record.id);
      batch.set(ref, record.data);

      if (record.subCollections) {
        for (const [subColName, subRecords] of Object.entries(record.subCollections)) {
          await restoreRecords(ref.collection(subColName), subRecords);
        }
      }
    }

    await batch.commit();
    written += chunk.length;
    process.stdout.write(`\r  已還原 ${written} / ${records.length} 筆...`);
  }

  process.stdout.write('\n');
  return written;
}

async function main() {
  const args      = parseArgs();
  const s3Prefix  = args['s3-prefix'] || null;
  const backupDir = args.backup ? path.resolve(args.backup) : null;
  const targetCol = args.collection || null;
  const wipeFirst = !!args.wipe;

  if (!s3Prefix && !backupDir) {
    console.error('❌ 請指定來源：');
    console.error('   --s3-prefix=<S3 前綴路徑>   從 AWS S3 還原');
    console.error('   --backup=<本地目錄路徑>       從本地備份還原');
    process.exit(1);
  }

  let manifest;
  let sourceLabel;

  if (s3Prefix) {
    // ── S3 來源 ──────────────────────────────────
    if (!S3_BUCKET) {
      console.error('❌ 缺少環境變數：AWS_S3_BUCKET');
      process.exit(1);
    }
    sourceLabel = `s3://${S3_BUCKET}/${s3Prefix}/`;
    console.log(`\n☁️  從 S3 載入 manifest...`);
    try {
      manifest = await getS3Json(`${s3Prefix}/manifest.json`);
    } catch {
      console.error(`❌ 找不到 S3 manifest：${s3Prefix}/manifest.json`);
      process.exit(1);
    }
  } else {
    // ── 本地來源（向下相容）──────────────────────
    if (!fs.existsSync(backupDir)) {
      console.error(`❌ 備份目錄不存在: ${backupDir}`);
      process.exit(1);
    }
    sourceLabel = backupDir;
    try {
      manifest = JSON.parse(fs.readFileSync(path.join(backupDir, 'manifest.json'), 'utf8'));
    } catch {
      console.error(`❌ 找不到或無法讀取 manifest.json`);
      process.exit(1);
    }
  }

  console.log(`\n🔄 Firebase Restore`);
  console.log(`   備份來源   : ${sourceLabel}`);
  console.log(`   備份時間   : ${manifest.exportedAt}`);
  console.log(`   目標       : ${targetCol || '全部 Collection'}`);
  console.log(`   模式       : ${wipeFirst ? '⚠️  先清空再還原 (WIPE)' : '直接覆蓋還原'}\n`);

  const availableCols = Object.keys(manifest.collections);
  const targetCols = targetCol
    ? (availableCols.includes(targetCol) ? [targetCol] : null)
    : availableCols;

  if (!targetCols) {
    console.error(`❌ 備份中找不到 Collection: ${targetCol}`);
    console.error(`   可用: ${availableCols.join(', ')}`);
    process.exit(1);
  }

  if (wipeFirst) {
    console.warn(`⚠️  警告：即將永久刪除以下 Collection 的所有現有資料：`);
    targetCols.forEach(c => console.warn(`   - ${c}`));
    const ok = await confirm('\n確定要清空並重建嗎？');
    if (!ok) {
      console.log('已取消。');
      process.exit(0);
    }
  }

  const t0 = Date.now();

  for (const colName of targetCols) {
    let records;

    if (s3Prefix) {
      // 從 S3 下載
      const s3Key = manifest.collections[colName].s3Key || `${s3Prefix}/${colName}.json`;
      process.stdout.write(`☁️  下載 ${colName} (${s3Key})...\n`);
      try {
        records = await getS3Json(s3Key);
      } catch {
        console.warn(`⚠️  找不到 S3 物件: ${s3Key}，跳過`);
        continue;
      }
    } else {
      // 從本地讀取
      const colFile = path.join(backupDir, manifest.collections[colName].file || `${colName}.json`);
      if (!fs.existsSync(colFile)) {
        console.warn(`⚠️  找不到備份檔: ${colFile}，跳過`);
        continue;
      }
      records = JSON.parse(fs.readFileSync(colFile, 'utf8'));
    }

    if (wipeFirst) {
      process.stdout.write(`🗑️  清空 ${colName} ...`);
      const deleted = await wipeCollection(db.collection(colName));
      process.stdout.write(` 已刪除 ${deleted} 筆\n`);
    }

    process.stdout.write(`📥 還原 ${colName} (${records.length} 筆)...\n`);
    await restoreRecords(db.collection(colName), records);
    console.log(`   ✅ ${colName} 還原完成`);
  }

  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  console.log(`\n✅ 全部還原完成，耗時 ${elapsed}s\n`);
  process.exit(0);
}

main().catch(err => {
  console.error(`\n❌ 還原失敗: ${err.message}`);
  process.exit(1);
});
