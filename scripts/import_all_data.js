require("dotenv").config();
const admin = require("firebase-admin");
const axios = require("axios");
const fs = require("fs");
const csv = require("csv-parser");
const { Readable } = require("stream");
const proj4 = require("proj4");

// ==========================================
// 系統初始化與設定
// ==========================================

// 定義 TWD97 座標系統參數 (供警察局資料使用)
proj4.defs("EPSG:3826", "+proj=tmerc +lat_0=0 +lon_0=121 +k=0.9999 +x_0=250000 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs");

// ─── 環境變數驗證 ────────────────────────────────────
const GOOGLE_API_KEY = process.env.GOOGLE_GEOCODING_API_KEY;

if (!GOOGLE_API_KEY) {
  console.error("❌ 缺失環境變數：GOOGLE_GEOCODING_API_KEY");
  console.error("請確保 .env 檔案中已設定此值");
  process.exit(1);
}

// 1. 初始化 Firebase Admin
const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});
const db = admin.firestore();

console.log("✅ 環境變數已載入");
console.log("✅ Firebase Admin 已初始化\n");

// ==========================================
// 全域資料庫設定檔 (共 16 份大嘉義地區資料)
// ==========================================
const DATA_SOURCES = [
  // --- 嘉義市 API (具備完整座標) ---
  { collectionName: "parking_lots", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=d206db33-3ae7-489e-b709-5555222fb767&rid=4e0c8e01-9844-4da6-991b-a3382b51b71b", latKey: "py", lngKey: "px" },
  { collectionName: "gas_stations", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=c9d3f398-7a91-404d-b9b3-5da23c7427a8&rid=007fc48d-a4c5-4417-8300-205c2c3dc8cf", latKey: "緯度坐標", lngKey: "經度坐標" },
  { collectionName: "ev_charging_stations", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=b1374d17-e503-49e1-9406-af2d323807f4&rid=14061c83-6aaf-4c54-8a1c-59c891eabda7", latKey: "緯度", lngKey: "經度" },
  { collectionName: "taxi_stands", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=61f7bf2d-428a-454a-919e-d637c5d3aa73&rid=61b77109-09dd-484e-9c1f-9b69b1205e86", latKey: "緯度", lngKey: "經度" },
  { collectionName: "good_shops", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=0a9be9b0-5da6-4df6-96f9-57b26da97e6c&rid=b37989c3-63b4-446f-b999-e7ca64263533", latKey: "緯度", lngKey: "經度" },
  { collectionName: "wheelchair_stations", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=2ec3a494-3282-43d4-a7fe-1f33019c898f&rid=73b4e333-0c52-4dc3-8aa3-e597ffacb932", latKey: "緯度", lngKey: "經度" },
  { collectionName: "pet_friendly_shops", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=10efc492-7ed4-4e4f-8f3e-4d337b92812b&rid=925b6280-40e3-48ff-a3db-773ba874fcc5", latKey: "緯度", lngKey: "經度" },
  { collectionName: "breastfeeding_rooms", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=5578a69f-b7f1-4fb8-bc43-f5da71949818&rid=514e8600-71e8-4595-a1fb-090998e7a01f", latKey: "緯度", lngKey: "經度" },
  { collectionName: "public_toilets", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=9b419009-88bc-42c7-bbaa-79a7e254c223&rid=16d7cb12-ae85-4459-b913-0ac004fc7194", latKey: "緯度", lngKey: "經度" },

  // --- 嘉義市 API (無座標，需透過 Google API 轉換地址) ---
  { collectionName: "excellent_drink_shops", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=afe633c0-7a97-4ad1-8587-d07f983401e2&rid=33516fe7-fa11-417a-9043-0f04135a9ffb", addressKey: "地址" },
  { collectionName: "excellent_restaurants", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=5f69dca6-8f7f-41c9-a43c-3df83c7a66c4&rid=9791920e-7e20-4407-8a4f-9c5487ccc93c", addressKey: "地址" },

  // --- 本機 CSV (全國資料，腳本自動過濾出「嘉義」並處理特定座標) ---
  { collectionName: "aed_locations", sourceType: "csv", path: "./AED.csv", latKey: "地點LAT", lngKey: "地點LNG", filterKey: "場所縣市", filterKeyword: "嘉義" },
  { collectionName: "itaiwan_hotspots", sourceType: "csv", path: "./iTaiwan.csv", latKey: "Latitude", lngKey: "Longitude", filterKey: "Area", filterKeyword: "嘉義" },
  { collectionName: "police_stations", sourceType: "csv", path: "./PoliceAddress.csv", latKey: "POINT_Y", lngKey: "POINT_X", filterKey: "地址", filterKeyword: "嘉義", isTWD97: true },

  // --- 嘉義縣 CSV (無座標，需透過 Google API 轉換) ---
  { collectionName: "county_gas_stations", sourceType: "csv", path: "./chiayicounty_gas_station.csv", addressKey: "營業地址" },
  { collectionName: "county_parking_lots", sourceType: "csv", path: "./chiayicounty_parkring.csv", combineAddress: true },

  // --- 嘉義市旅遊服務中心與借問站 ---
  { collectionName: "facilities", sourceType: "api", path: "https://data.chiayi.gov.tw/opendata/api/getResource?oid=dca09031-9e55-4edc-a69f-f752c8e1aedf&rid=2be2eb73-ce0d-4247-ac3a-430cdb8226ce", latKey: "緯度", lngKey: "經度", isCsv: true }
];

// ==========================================
// 核心處理邏輯區
// ==========================================

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function getCoordinates(address) {
  if (!GOOGLE_API_KEY) {
    console.warn(`    ⚠️ 未設定 Google API Key，跳過: ${address}`);
    return null;
  }
  try {
    const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${GOOGLE_API_KEY}&language=zh-TW`;
    const response = await axios.get(url);
    if (response.data.status === "OK") return response.data.results[0].geometry.location;
    console.warn(`    ⚠️ Google 找不到此地址: ${address}`);
    return null;
  } catch (error) {
    console.error(`    ❌ Geocoding 請求失敗:`, error.message);
    return null;
  }
}

async function processApiSource(config) {
  console.log(`[API] 正在下載 ${config.collectionName} ...`);
  const response = await axios.get(config.path);
  let data = response.data;

  if (typeof data === 'object') {
    if (Array.isArray(data)) return data;
    if (data.result && Array.isArray(data.result.records)) return data.result.records;
  }

  if (typeof data === 'string' || config.isCsv) {
    const rawStr = typeof data === 'string' ? data : JSON.stringify(data);
    console.log(`  -> 偵測到 CSV 純文字格式，啟動記憶體轉換...`);
    return new Promise((resolve, reject) => {
      const results = [];
      Readable.from([typeof data === 'string' ? data : rawStr]).pipe(csv())
        .on("data", (row) => results.push(row))
        .on("end", () => resolve(results))
        .on("error", (err) => reject(err));
    });
  }
  throw new Error(`無法解析 API 格式`);
}

function processCsvSource(config) {
  console.log(`[CSV] 正在讀取 ${config.collectionName} ...`);
  return new Promise((resolve, reject) => {
    const results = [];
    if (!fs.existsSync(config.path)) return reject(new Error(`找不到檔案: ${config.path}`));

    fs.createReadStream(config.path)
      .pipe(csv())
      .on("data", (data) => results.push(data))
      .on("end", () => resolve(results))
      .on("error", (err) => reject(err));
  });
}

// 根據 collection 產生穩定的 document ID（避免重複執行時資料疊加）
function getDocId(item, collectionName) {
  const clean = (str) => String(str || "").trim().replace(/\s+/g, "_").replace(/[/\\]/g, "-");
  switch (collectionName) {
    case "parking_lots":        return clean(item["停車場名稱"]);
    case "gas_stations":        return clean(item["編號"]);
    case "ev_charging_stations":return clean(item["編號"]);
    case "taxi_stands":         return clean(`${item["緯度"]}_${item["經度"]}`);
    case "good_shops":          return clean(`${item["店家名稱"]}_${item["地址"]}`);
    case "wheelchair_stations": return clean(item["編號"]);
    case "pet_friendly_shops":  return clean(`${item["店家名稱"]}_${item["地址"]}`);
    case "breastfeeding_rooms": return clean(`${item["公共場所名稱"]}_${item["地址"]}`);
    case "public_toilets":      return clean(`${item["名稱"]}_${item["地址"]}`);
    case "excellent_drink_shops":   return clean(item["食品業者登錄字號"]);
    case "excellent_restaurants":   return clean(item["食品業者登錄字號"]);
    case "aed_locations":       return clean(item["場所ID"]);
    case "itaiwan_hotspots":    return clean(`${item["Latitude"]}_${item["Longitude"]}`);
    case "police_stations":     return clean(item["中文單位名稱"]);
    case "county_gas_stations": return clean(item["營業地址"]);
    case "county_parking_lots": return clean(`${item["鄉鎮市"]}_${item["停車場名稱"]}`);
    case "facilities":          return clean(`${item["名稱"]}_${item["地址"]}`);
    default:                    return null; // fallback: 用隨機 ID
  }
}

async function writeToFirestore(dataList, config) {
  console.log(`準備處理 ${dataList.length} 筆原始資料寫入 ${config.collectionName}...`);
  let batch = db.batch();
  let count = 0;
  let totalUploaded = 0;
  const collectionRef = db.collection(config.collectionName);

  let currentTown = ""; // 用來記憶鄉鎮市的變數

  for (const item of dataList) {

    // 防呆1：遇到「合計」直接跳過不處理
    if (item['序號'] && item['序號'].includes("合計")) {
      continue;
    }

    // 防呆2：自動修復 Excel 合併儲存格產生的空白鄉鎮市
    if (config.collectionName === "county_parking_lots") {
      if (item['鄉鎮市'] && item['鄉鎮市'].trim() !== "") {
        currentTown = item['鄉鎮市'].trim(); 
      } else {
        item['鄉鎮市'] = currentTown; 
      }
    }

    // 本機資料過濾 (針對全國資料過濾「嘉義」)
    if (config.filterKey && config.filterKeyword) {
      const targetText = item[config.filterKey] || "";
      if (!targetText.includes(config.filterKeyword)) continue;
    }

    let lat = item[config.latKey];
    let lng = item[config.lngKey];
    let addressToSearch = null;

    // 動態地址組合與轉換
    if (config.addressKey && item[config.addressKey]) {
      addressToSearch = item[config.addressKey]; 
    } else if (config.combineAddress && item['鄉鎮市'] && item['停車場名稱']) {
      addressToSearch = `嘉義縣${item['鄉鎮市']}${item['停車場名稱']}`; 
    }

    if ((!lat || !lng) && addressToSearch) {
      console.log(`    🔍 正在向 Google 查詢座標: ${addressToSearch}...`);
      await sleep(200); 
      const geoData = await getCoordinates(addressToSearch);
      if (geoData) {
        lat = geoData.lat;
        lng = geoData.lng;
      }
    }

    // 經緯度型別轉換與 TWD97 轉換
    if (lat && lng) {
      let parsedLat = parseFloat(lat);
      let parsedLng = parseFloat(lng);

      if (!isNaN(parsedLat) && !isNaN(parsedLng)) {
        if (config.isTWD97) {
          const [wgsLng, wgsLat] = proj4("EPSG:3826", "EPSG:4326", [parsedLng, parsedLat]);
          parsedLat = wgsLat;
          parsedLng = wgsLng;
        }
        item.location = new admin.firestore.GeoPoint(parsedLat, parsedLng);
      }
    }

    // 批次寫入資料庫（使用穩定 ID 做 upsert，避免重複執行時資料疊加）
    const docId = getDocId(item, config.collectionName);
    const docRef = docId ? collectionRef.doc(docId) : collectionRef.doc();
    batch.set(docRef, item);
    count++;

    if (count === 500) {
      await batch.commit();
      totalUploaded += count;
      batch = db.batch();
      count = 0;
    }
  }

  if (count > 0) {
    await batch.commit();
    totalUploaded += count;
  }
  console.log(`✅ ${config.collectionName} 篩選與寫入完成，實際匯入共 ${totalUploaded} 筆。\n`);
}

async function runAllTasks() {
  console.log("🚀 開始執行全域資料同步管線...\n");
  for (const config of DATA_SOURCES) {
    try {
      let dataList = config.sourceType === "api" ? await processApiSource(config) : await processCsvSource(config);
      await writeToFirestore(dataList, config);
    } catch (error) {
      console.error(`❌ 處理 ${config.collectionName} 時發生錯誤: ${error.message}\n`);
    }
  }
  console.log("🎉 所有大嘉義空間資料同步完畢！您的資料庫已準備就緒！");
  process.exit(0);
}

runAllTasks();
