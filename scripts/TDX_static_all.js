require('dotenv').config();
const admin = require('firebase-admin');
const axios = require('axios');

// ═══════════════════════════════════════════════════════
// 1. 初始化 Firebase Admin
// ═══════════════════════════════════════════════════════
const serviceAccount = require('./serviceAccountKey.json');
if (admin.apps.length === 0) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

// ═══════════════════════════════════════════════════════
// 2. TDX 憑證
// ═══════════════════════════════════════════════════════
const TDX_CLIENT_ID = process.env.TDX_CLIENT_ID;
const TDX_CLIENT_SECRET = process.env.TDX_CLIENT_SECRET;
// ═══════════════════════════════════════════════════════
// 3. 共用工具函式
// ═══════════════════════════════════════════════════════
async function getTdxToken() {
    const tokenUrl = 'https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token';
    const params = new URLSearchParams();
    params.append('grant_type', 'client_credentials');
    params.append('client_id', TDX_CLIENT_ID);
    params.append('client_secret', TDX_CLIENT_SECRET);
    try {
        const response = await axios.post(tokenUrl, params);
        return response.data.access_token;
    } catch (error) {
        console.error('❌ 取得 TDX Token 失敗:', error.response ? error.response.data : error.message);
        return null;
    }
}

function chunkArray(arr, size) {
    const result = [];
    for (let i = 0; i < arr.length; i += size) result.push(arr.slice(i, i + size));
    return result;
}

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function axiosGetWithRetry(url, options) {
    const maxRetries = 3;
    const retryDelay = 10000;
    let lastError;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            return await axios.get(url, options);
        } catch (err) {
            lastError = err;
            const status = err.response && err.response.status;
            const msg = (err.response && err.response.data && err.response.data.message) || '';
            const isRateLimit = status === 429 || msg.toLowerCase().includes('rate limit');
            if (isRateLimit && attempt < maxRetries) {
                console.warn(`  ⚠️  Rate limit，等待 ${retryDelay / 1000} 秒後重試（${attempt}/${maxRetries}）...`);
                await sleep(retryDelay);
            } else break;
        }
    }
    throw lastError;
}

async function batchWrite(collectionName, dataArray, getDocRef) {
    const chunks = chunkArray(dataArray, 400);
    console.log(`  📦 共 ${dataArray.length} 筆，分 ${chunks.length} 包寫入 '${collectionName}'...`);
    let total = 0;
    for (let i = 0; i < chunks.length; i++) {
        const batch = db.batch();
        chunks[i].forEach(item => batch.set(getDocRef(item), item));
        await batch.commit();
        total += chunks[i].length;
        console.log(`  ✔️ 第 ${i + 1} 包完成 (${total}/${dataArray.length})`);
    }
}

const TARGET_CITIES = [
    { id: 'Chiayi', name: '嘉義市' },
    { id: 'ChiayiCounty', name: '嘉義縣' }
];

// ═══════════════════════════════════════════════════════
// 4. 同步景點 → places
// ═══════════════════════════════════════════════════════
async function syncScenicSpots(token) {
    console.log('\n🔄 【景點】開始同步...');
    let all = [];
    for (const city of TARGET_CITIES) {
        console.log(`  抓取 ${city.name}...`);
        const res = await axiosGetWithRetry(
            `https://tdx.transportdata.tw/api/basic/v2/Tourism/ScenicSpot/${city.id}?%24format=JSON`,
            { headers: { 'Authorization': `Bearer ${token}` } }
        );
        all = all.concat(res.data.map(s => ({ ...s, _CityName: city.name })));
        await sleep(2000);
    }
    console.log(`  ✅ 共 ${all.length} 筆`);
    const formatted = all.map(spot => ({
        id: spot.ScenicSpotID,
        name: spot.ScenicSpotName,
        descriptionDetail: spot.DescriptionDetail || '',
        description: spot.Description || '',
        phone: spot.Phone || '無電話資訊',
        address: spot.Address || '無地址資訊',
        travelInfo: spot.TravelInfo || '',
        openTime: spot.OpenTime || '無營業時間資訊',
        remarks: spot.Remarks || '',
        pictureUrl: spot.Picture?.PictureUrl1 || '',
        websiteUrl: spot.WebsiteUrl || '',
        location: new admin.firestore.GeoPoint(
            spot.Position?.PositionLat || 0, 
            spot.Position?.PositionLon || 0
        ),
        city: spot.City || spot._CityName,
        classes: [spot.Class1, spot.Class2, spot.Class3].filter(Boolean),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }));
    await batchWrite('places', formatted, d => db.collection('tdx_spots').doc(d.id));
    console.log(`🎉 景點完成！共 ${formatted.length} 筆`);
}

// ═══════════════════════════════════════════════════════
// 5. 同步旅宿 → hotels
// ═══════════════════════════════════════════════════════
async function syncHotels(token) {
    console.log('\n🔄 【旅宿】開始同步...');
    let all = [];
    for (const city of TARGET_CITIES) {
        console.log(`  抓取 ${city.name}...`);
        const res = await axiosGetWithRetry(
            `https://tdx.transportdata.tw/api/basic/v2/Tourism/Hotel/${city.id}`,
            { headers: { 'Authorization': `Bearer ${token}` }, params: { '$top': 3000, '$format': 'JSON' } }
        );
        console.log(`  ✅ 抓到 ${res.data.length} 筆`);
        all = all.concat(res.data.map(h => ({ ...h, _CityName: city.name })));
        await sleep(2000);
    }
    const formatted = all.map(hotel => {
        const lat = hotel.Position?.PositionLat;
        const lon = hotel.Position?.PositionLon;
        return {
            id: hotel.HotelID,
            name: hotel.HotelName,
            description: hotel.Description || '無旅宿介紹',
            address: hotel.Address || '無地址資訊',
            phone: hotel.Phone || '無電話資訊',
            pictureUrl: hotel.Picture?.PictureUrl1 || '',
            pictureDescription: hotel.Picture?.PictureDescription1 || '',
            location: (lat && lon) ? new admin.firestore.GeoPoint(parseFloat(lat), parseFloat(lon)) : null,
            hotelClass: hotel.Class || '一般旅館',
            parkingInfo: hotel.ParkingInfo || '無提供車位資訊',
            serviceInfo: hotel.ServiceInfo || '無提供設施服務',
            spec: hotel.Spec || '暫無房價資訊',
            city: hotel.City || hotel._CityName || '嘉義',
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
    });
    await batchWrite('hotels', formatted, d => db.collection('tdx_hotels').doc(d.id));
    console.log(`🎉 旅宿完成！共 ${formatted.length} 筆`);
}

// ═══════════════════════════════════════════════════════
// 6. 同步公車路線 + 去重實體站牌 → bus_routes, bus_stops
// ═══════════════════════════════════════════════════════
async function syncBusRoutes(token) {
    console.log('\n🔄 【公車路線 + 站牌去重】開始同步...');
    let allRoutes = [];
    for (const city of TARGET_CITIES) {
        console.log(`  抓取 ${city.name}...`);
        const res = await axiosGetWithRetry(
            `https://tdx.transportdata.tw/api/basic/v2/Bus/StopOfRoute/City/${city.id}`,
            { headers: { 'Authorization': `Bearer ${token}` }, params: { '$top': 3000, '$format': 'JSON' } }
        );
        console.log(`  ✅ 抓到 ${res.data.length} 筆路線（含去回程）`);
        allRoutes = allRoutes.concat(res.data.map(r => ({ ...r, _CityName: city.name })));
        await sleep(2000);
    }

    const formattedRoutes = [];
    const uniqueStopsMap = new Map();

    allRoutes.forEach(route => {
        const routeUID = route.RouteUID;
        const routeName = route.RouteName?.Zh_tw || '未命名路線';
        const direction = route.Direction;
        const directionText = direction === 0 ? '去程' : (direction === 1 ? '返程' : '其他');
        const uniqueRouteId = `${routeUID}_${direction}`;
        const formattedStops = [];

        (route.Stops || []).forEach(stop => {
            const lat = stop.StopPosition?.PositionLat;
            const lon = stop.StopPosition?.PositionLon;
            const stopName = stop.StopName?.Zh_tw || '未命名站牌';
            const validLocation = (lat && lon)
                ? new admin.firestore.GeoPoint(parseFloat(lat), parseFloat(lon)) : null;

            formattedStops.push({
                StopUID: stop.StopUID,
                StopName: stopName,
                StopSequence: stop.StopSequence,
                location: validLocation
            });

            // 去重站牌（以站名 + 縣市為 key，保留最多兩側座標）
            if (lat && lon) {
                const nameKey = `${stopName}_${route._CityName}`;
                const routeInfoStr = `${routeName} (${directionText})`;
                if (!uniqueStopsMap.has(nameKey)) {
                    uniqueStopsMap.set(nameKey, {
                        id: nameKey.replace(/\s/g, '_'),
                        StopName: stopName,
                        locations: [validLocation],  // 主座標（地圖顯示用）
                        city: route._CityName,
                        passingRoutes: [routeInfoStr],
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                } else {
                    const existing = uniqueStopsMap.get(nameKey);
                    // 不同座標才加入（來回對面站牌），最多保留兩個
                    const alreadyHasCoord = existing.locations.some(
                        loc => loc.latitude === parseFloat(lat) && loc.longitude === parseFloat(lon)
                    );
                    if (!alreadyHasCoord && existing.locations.length < 2) {
                        existing.locations.push(validLocation);
                    }
                    if (!existing.passingRoutes.includes(routeInfoStr))
                        existing.passingRoutes.push(routeInfoStr);
                }
            }
        });

        formattedRoutes.push({
            id: uniqueRouteId,
            RouteUID: routeUID,
            RouteName: routeName,
            Direction: direction,
            city: route.City || route._CityName || '嘉義',
            stops: formattedStops,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
    });

    const formattedUniqueStops = Array.from(uniqueStopsMap.values());
    console.log(`  🧩 產出 ${formattedRoutes.length} 條路線，${formattedUniqueStops.length} 個不重複站牌`);

    await batchWrite('bus_routes', formattedRoutes, d => db.collection('tdx_bus_routes').doc(d.id));
    await batchWrite('bus_stops', formattedUniqueStops, d => db.collection('tdx_bus_stops').doc(d.id));
    console.log('🎉 公車路線與站牌完成！');
}

// ═══════════════════════════════════════════════════════
// 7. 同步公車時刻表 → bus_schedules
// ═══════════════════════════════════════════════════════
async function syncBusSchedules(token) {
    console.log('\n🔄 【公車時刻表】開始同步...');
    let all = [];
    for (const city of TARGET_CITIES) {
        console.log(`  抓取 ${city.name}...`);
        const res = await axiosGetWithRetry(
            `https://tdx.transportdata.tw/api/basic/v2/Bus/Schedule/City/${city.id}`,
            { headers: { 'Authorization': `Bearer ${token}` }, params: { '$top': 3000, '$format': 'JSON' } }
        );
        console.log(`  ✅ 抓到 ${res.data.length} 筆`);
        all = all.concat(res.data.map(s => ({ ...s, _CityName: city.name })));
        await sleep(2000);
    }
    const formatted = all.map(schedule => {
        const uniqueId = `${schedule.RouteUID}_${schedule.Direction}`;
        const trips = (schedule.Timetables || []).map(trip => ({
            TripID: trip.TripID || '未知班次',
            StopTimes: (trip.StopTimes || []).map(stop => ({
                StopSequence: stop.StopSequence,
                StopUID: stop.StopUID,
                StopName: stop.StopName?.Zh_tw || '未知站牌',
                ArrivalTime: stop.ArrivalTime || '未知時間'
            }))
        }));
        return {
            id: uniqueId,
            RouteUID: schedule.RouteUID,
            RouteName: schedule.RouteName?.Zh_tw || '未命名路線',
            Direction: schedule.Direction,
            city: schedule.City || schedule._CityName || '嘉義',
            Trips: trips,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
    });
    await batchWrite('bus_schedules', formatted, d => db.collection('tdx_bus_schedules').doc(d.id));
    console.log(`🎉 公車時刻表完成！共 ${formatted.length} 筆`);
}

// ═══════════════════════════════════════════════════════
// 8. 同步 YouBike 站點 → youbike_stations
// ═══════════════════════════════════════════════════════
async function syncYouBikeStations(token) {
    console.log('\n🔄 【YouBike 靜態站點】開始同步...');
    let all = [];
    for (const city of TARGET_CITIES) {
        console.log(`  抓取 ${city.name}...`);
        const res = await axiosGetWithRetry(
            `https://tdx.transportdata.tw/api/basic/v2/Bike/Station/City/${city.id}`,
            { headers: { 'Authorization': `Bearer ${token}` }, params: { '$top': 3000, '$format': 'JSON' } }
        );
        console.log(`  ✅ 抓到 ${res.data.length} 筆`);
        all = all.concat(res.data.map(s => ({ ...s, _CityName: city.name })));
        await sleep(2000);
    }
    const formatted = all.map(station => {
        const lat = station.StationPosition?.PositionLat;
        const lon = station.StationPosition?.PositionLon;
        return {
            StationUID: station.StationUID,
            StationName: station.StationName?.Zh_tw || '未命名站點',
            location: (lat && lon) ? new admin.firestore.GeoPoint(parseFloat(lat), parseFloat(lon)) : null,
            city: station.City || station._CityName || '嘉義',
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
    });
    await batchWrite('youbike_stations', formatted, d => db.collection('tdx_youbike_stations').doc(d.StationUID));
    console.log(`🎉 YouBike 站點完成！共 ${formatted.length} 筆`);
}

// ═══════════════════════════════════════════════════════
// 9. 同步台鐵時刻表 → tra_schedules
// ═══════════════════════════════════════════════════════
async function syncTraSchedules(token) {
    console.log('\n🔄 【台鐵時刻表】開始同步...');
    const chiayiStationIDs = ['3130', '3140', '3150', '3160', '3170', '3180'];
    const res = await axiosGetWithRetry(
        'https://tdx.transportdata.tw/api/basic/v3/Rail/TRA/GeneralTrainTimetable',
        { headers: { 'Authorization': `Bearer ${token}` }, params: { '$format': 'JSON' } }
    );
    const timetables = res.data.TrainTimetables || res.data;
    console.log(`  ✅ 全台共 ${timetables.length} 筆，過濾嘉義站中...`);

    const formatted = [];
    timetables.forEach(item => {
        const trainInfo = item.TrainInfo || {};
        const stopTimesRaw = item.StopTimes || [];
        const serviceDay = item.ServiceDay || {};
        if (!stopTimesRaw.some(s => chiayiStationIDs.includes(s.StationID))) return;

        const uniqueId = `${trainInfo.TrainNo}_${trainInfo.Direction}`;
        formatted.push({
            id: uniqueId,
            TrainNo: trainInfo.TrainNo,
            Direction: trainInfo.Direction,
            TrainTypeName: trainInfo.TrainTypeName?.Zh_tw || '未知車種',
            StartingStationName: trainInfo.StartingStationName?.Zh_tw || '未知起點',
            EndingStationName: trainInfo.EndingStationName?.Zh_tw || '未知終點',
            serviceDays: {
                Monday: serviceDay.Monday || 0,
                Tuesday: serviceDay.Tuesday || 0,
                Wednesday: serviceDay.Wednesday || 0,
                Thursday: serviceDay.Thursday || 0,
                Friday: serviceDay.Friday || 0,
                Saturday: serviceDay.Saturday || 0,
                Sunday: serviceDay.Sunday || 0,
                NationalHolidays: serviceDay.NationalHolidays || 0
            },
            stopTimes: stopTimesRaw.map(s => ({
                StopSequence: s.StopSequence,
                StationID: s.StationID,
                StationName: s.StationName?.Zh_tw || '未知車站',
                ArrivalTime: s.ArrivalTime || '---',
                DepartureTime: s.DepartureTime || '---'
            })),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
    });

    console.log(`  🎯 過濾完成，共 ${formatted.length} 班行經嘉義`);
    await batchWrite('tra_schedules', formatted, d => db.collection('tdx_tra_schedules').doc(d.id));
    console.log(`🎉 台鐵時刻表完成！`);
}

// ═══════════════════════════════════════════════════════
// 10. 同步阿里山林鐵時刻表 → alishan_rail_schedules
// ═══════════════════════════════════════════════════════
async function syncAlishanRail(token) {
    console.log('\n🔄 【阿里山林鐵時刻表】開始同步...');
    const res = await axiosGetWithRetry(
        'https://tdx.transportdata.tw/api/basic/v3/Rail/AFR/GeneralTrainTimetable',
        { headers: { 'Authorization': `Bearer ${token}` }, params: { '$top': 3000, '$format': 'JSON' } }
    );
    const timetables = res.data.TrainTimetables || res.data;
    console.log(`  ✅ 共 ${timetables.length} 筆車次`);

    const formatted = timetables.map(item => {
        const trainInfo = item.TrainInfo || {};
        const serviceDay = item.ServiceDay || {};
        const uniqueId = `${trainInfo.TrainNo}_${trainInfo.Direction}`;
        return {
            id: uniqueId,
            TrainNo: trainInfo.TrainNo,
            Direction: trainInfo.Direction,
            TripHeadSign: trainInfo.TripHeadSign || '',
            serviceDays: {
                Monday: serviceDay.Monday || 0,
                Tuesday: serviceDay.Tuesday || 0,
                Wednesday: serviceDay.Wednesday || 0,
                Thursday: serviceDay.Thursday || 0,
                Friday: serviceDay.Friday || 0,
                Saturday: serviceDay.Saturday || 0,
                Sunday: serviceDay.Sunday || 0,
                NationalHolidays: serviceDay.NationalHolidays || 0
            },
            stopTimes: (item.StopTimes || []).map(s => ({
                StopSequence: s.StopSequence,
                StationID: s.StationID,
                StationName: s.StationName?.Zh_tw || '未知車站',
                ArrivalTime: s.ArrivalTime || '---',
                DepartureTime: s.DepartureTime || '---'
            })),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
    });

    await batchWrite('alishan_rail_schedules', formatted, d => db.collection('tdx_alishan_rail_schedules').doc(d.id));
    console.log(`🎉 阿里山林鐵完成！共 ${formatted.length} 筆`);
}

// ═══════════════════════════════════════════════════════
// 11. 主程式
// ═══════════════════════════════════════════════════════
async function syncAll() {
    console.log('🚀 開始靜態資料全同步（嘉義縣市）\n');
    const token = await getTdxToken();
    if (!token) { console.error('❌ 無法取得 TDX Token，終止。'); return; }

    const tasks = [
        { name: '景點',        fn: () => syncScenicSpots(token) },
        { name: '旅宿',        fn: () => syncHotels(token) },
        { name: '公車路線',    fn: () => syncBusRoutes(token) },
        { name: '公車時刻表',  fn: () => syncBusSchedules(token) },
        { name: 'YouBike站點', fn: () => syncYouBikeStations(token) },
        { name: '台鐵時刻表',  fn: () => syncTraSchedules(token) },
        { name: '阿里山林鐵',  fn: () => syncAlishanRail(token) },
    ];

    for (let i = 0; i < tasks.length; i++) {
        try {
            await tasks[i].fn();
        } catch (err) {
            console.error(`❌ 【${tasks[i].name}】同步失敗:`, err.response ? err.response.data : err.message);
        }
        if (i < tasks.length - 1) {
            console.log('  ⏳ 等待 15 秒避免 Rate Limit...');
            await sleep(15000);
        }
    }

    console.log('\n✅ 所有靜態資料同步完成！');
    process.exit(0);
}

syncAll();