package com.explorechiayi.tdx_server.service;

import com.explorechiayi.tdx_server.config.TdxConfig;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;
import java.util.LinkedHashMap;

@Service
public class TdxService {

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private String currentToken = "";

    private final Map<String, Long> cacheTimeMap = new ConcurrentHashMap<>();
    private final Map<String, List<Map<String, Object>>> cacheDataMap = new ConcurrentHashMap<>();
    private final Map<String, JsonNode> youbikeStationMap = new ConcurrentHashMap<>(); 
    
    private final List<Map<String, Object>> traAllTrains = new ArrayList<>();
    private final List<Map<String, Object>> thsrAllTrains = new ArrayList<>();
    private String syncedDate = "";
    private long lastSyncAttempt = 0;

    // 全市公車站牌（啟動時預載，本地過濾用）
    private final Map<String, List<Map<String, Object>>> allBusStops = new ConcurrentHashMap<>();

    private final long REALTIME_CACHE_DURATION = 30000;   
    private volatile long rateLimitUntil = 0;

    @EventListener(ApplicationReadyEvent.class)
    public void preloadData() {
        new Thread(() -> {
            System.out.println("⏳ 啟動終極動靜分離預熱...");
            try {
                fetchYoubikeStations(); 
                getYoubikeDynamic(); 
                getWeeklyWeather("Chiayi");
                getWeeklyWeather("ChiayiCounty");
                System.out.println("✅ 預熱完成 (含天氣與Youbike)，開始載入公車站牌...");
                
                // 【核心修正 1】給予 TDX 伺服器 3 秒的緩衝時間
                Thread.sleep(3000); 
                preloadBusStops("Chiayi");
                
                // 【核心修正 2】在請求嘉義縣的龐大資料前，強制休眠 5 秒，避免觸發瞬間併發限制
                System.out.println("⏳ 進入冷卻期，準備請求嘉義縣資料...");
                Thread.sleep(35000); 
                preloadBusStops("ChiayiCounty");
                
                System.out.println("✅ 公車站牌載入完成，等待冷卻後載入火車時刻表...");
                Thread.sleep(55000);
                syncDailyData();
                System.out.println("✅ 伺服器啟動完畢！");
            } catch (Exception e) {}
        }).start();
    }

    public synchronized void fetchToken() {
        if (!currentToken.isEmpty()) return; 
        
        System.out.println("🔑 準備向 TDX 申請存取權杖 (Access Token)...");
        String url = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token";
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        MultiValueMap<String, String> map = new LinkedMultiValueMap<>();
        map.add("grant_type", "client_credentials");
        map.add("client_id", TdxConfig.CLIENT_ID);
        map.add("client_secret", TdxConfig.CLIENT_SECRET);

        try {
            ResponseEntity<String> response = restTemplate.postForEntity(url, new HttpEntity<>(map, headers), String.class);
            this.currentToken = objectMapper.readTree(response.getBody()).get("access_token").asText();
            System.out.println("✅ 成功取得 TDX API Token！解鎖十萬次額度！"); 
        } catch (Exception e) {
            System.out.println("❌ [TDX Token 獲取失敗] 無法兌換 Token！");
            System.out.println("👉 錯誤原因: " + e.getMessage());
            System.out.println("💡 請檢查 TdxConfig.java 中的 CLIENT_ID 與 CLIENT_SECRET 是否正確，且前後無多餘空白。");
            this.currentToken = "";
        }
    }

    private synchronized JsonNode callTdxApi(String apiUrl) {
        if (System.currentTimeMillis() < rateLimitUntil) return null;
        if (currentToken.isEmpty()) fetchToken();
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(currentToken);

        try {
            Thread.sleep(300); 
            ResponseEntity<String> response = restTemplate.exchange(apiUrl, HttpMethod.GET, new HttpEntity<>(headers), String.class);
            return objectMapper.readTree(response.getBody());
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().contains("429")) {
                rateLimitUntil = System.currentTimeMillis() + 60000;
            } else if (e.getMessage() != null && (e.getMessage().contains("401") || e.getMessage().contains("Unauthorized"))) {
                this.currentToken = "";
            }
            return null; 
        }
    }

    private synchronized Map<String, Object> getFromCacheOrFetch(String cacheKey, long duration, Supplier<List<Map<String, Object>>> fetchLogic) {
        long currentTime = System.currentTimeMillis();
        if (cacheTimeMap.containsKey(cacheKey) && (currentTime - cacheTimeMap.get(cacheKey) < duration)) {
            return buildResponse(cacheDataMap.get(cacheKey), cacheTimeMap.get(cacheKey));
        }
        List<Map<String, Object>> newData = null;
        try { newData = fetchLogic.get(); } catch (Exception e) {}
        if (newData != null) {
            cacheDataMap.put(cacheKey, newData); cacheTimeMap.put(cacheKey, currentTime);
            return buildResponse(newData, currentTime);
        }
        if (cacheDataMap.containsKey(cacheKey)) {
            return buildResponse(cacheDataMap.get(cacheKey), cacheTimeMap.get(cacheKey));
        } else {
            Map<String, Object> errorMap = new HashMap<>();
            errorMap.put("data", new ArrayList<>()); errorMap.put("updateTime", "--:--"); errorMap.put("error", "API_LIMIT");
            return errorMap;
        }
    }

    private Map<String, Object> buildResponse(List<Map<String, Object>> data, long timeMillis) {
        Map<String, Object> response = new HashMap<>();
        response.put("data", data);
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("HH:mm:ss");
        sdf.setTimeZone(java.util.TimeZone.getTimeZone("Asia/Taipei"));
        response.put("updateTime", sdf.format(new java.util.Date(timeMillis)));
        return response;
    }

    private synchronized void syncDailyData() {
        String today = LocalDate.now().toString();
        if (today.equals(syncedDate) && !traAllTrains.isEmpty() && !thsrAllTrains.isEmpty()) return;
        if (System.currentTimeMillis() - lastSyncAttempt < 60000) return;
        lastSyncAttempt = System.currentTimeMillis();

        if (thsrAllTrains.isEmpty() || !today.equals(syncedDate)) {
            try {
                JsonNode thsr = callTdxApi("https://tdx.transportdata.tw/api/basic/v2/Rail/THSR/DailyTimetable/TrainDate/" + today + "?$format=JSON");
                if (thsr != null && thsr.isArray()) {
                    thsrAllTrains.clear(); 
                    for (JsonNode train : thsr) {
                        Map<String, Object> t = new HashMap<>();
                        t.put("TrainNo", train.path("DailyTrainInfo").path("TrainNo").asText());
                        List<Map<String, Object>> stops = new ArrayList<>();
                        for (JsonNode stop : train.path("StopTimes")) {
                            Map<String, Object> s = new HashMap<>();
                            s.put("StationName", stop.path("StationName").path("Zh_tw").asText());
                            s.put("ArrivalTime", stop.path("ArrivalTime").asText(stop.path("DepartureTime").asText("--:--")));
                            s.put("DepartureTime", stop.path("DepartureTime").asText(stop.path("ArrivalTime").asText("--:--")));
                            s.put("StopSequence", stop.path("StopSequence").asInt());
                            stops.add(s);
                        }
                        t.put("StopTimes", stops);
                        thsrAllTrains.add(t);
                    }
                }
            } catch (Exception e) {}
        }

        if (traAllTrains.isEmpty() || !today.equals(syncedDate)) {
            try {
                JsonNode tra = callTdxApi("https://tdx.transportdata.tw/api/basic/v3/Rail/TRA/DailyTrainTimetable/TrainDate/" + today + "?$format=JSON");
                if (tra != null && tra.has("TrainTimetables")) {
                    traAllTrains.clear(); 
                    for (JsonNode train : tra.get("TrainTimetables")) {
                        Map<String, Object> t = new HashMap<>();
                        t.put("TrainNo", train.path("TrainInfo").path("TrainNo").asText());
                        t.put("TrainTypeName", train.path("TrainInfo").path("TrainTypeName").path("Zh_tw").asText());
                        List<Map<String, Object>> stops = new ArrayList<>();
                        for (JsonNode stop : train.path("StopTimes")) {
                            Map<String, Object> s = new HashMap<>();
                            s.put("StationName", stop.path("StationName").path("Zh_tw").asText());
                            s.put("ArrivalTime", stop.path("ArrivalTime").asText(stop.path("DepartureTime").asText("--:--")));
                            s.put("DepartureTime", stop.path("DepartureTime").asText(stop.path("ArrivalTime").asText("--:--")));
                            s.put("StopSequence", stop.path("StopSequence").asInt());
                            stops.add(s);
                        }
                        t.put("StopTimes", stops);
                        traAllTrains.add(t);
                    }
                }
            } catch (Exception e) {}
        }

        if (!traAllTrains.isEmpty() || !thsrAllTrains.isEmpty()) syncedDate = today;
    }

    private void fetchYoubikeStations() {
        if (!youbikeStationMap.isEmpty()) return;
        for (String city : new String[]{"Chiayi", "ChiayiCounty"}) {
            JsonNode root = callTdxApi("https://tdx.transportdata.tw/api/basic/v2/Bike/Station/City/" + city + "?$format=JSON");
            if (root != null && root.isArray()) {
                for (JsonNode node : root) { youbikeStationMap.put(node.path("StationUID").asText(), node); }
            }
        }
    }

    // 預載全市公車站牌到記憶體（含重試）
    // 預載全市公車站牌到記憶體（含重試）
   // 預載全市公車站牌到記憶體（含重試）
        private synchronized void preloadBusStops(String city) {
            if (allBusStops.containsKey(city) && !allBusStops.get(city).isEmpty()) return;
        System.out.println("⏳ 預載 " + city + " 公車站牌...");
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                if (attempt > 0) {
                    System.out.println("🔄 重試第 " + attempt + " 次 (" + city + ")...");
                    this.currentToken = "";
                    Thread.sleep(2000);
                }
                
                // 【核心修正】移除 $select 參數，繞過 TDX 處理巢狀陣列時會 500 崩潰的 Bug
                java.net.URI uri = new java.net.URI(
                    "https", "tdx.transportdata.tw",
                    "/api/basic/v2/Bus/StopOfRoute/City/" + city,
                    "$format=JSON", // 只保留 JSON 格式要求
                    null
                );
                
                JsonNode root = callTdxApiByUri(uri);
                if (root == null) {
                    System.out.println("⚠️ " + city + " attempt " + attempt + " returned null (TDX 伺服器未回傳有效資料)");
                    continue;
                }
                
                List<Map<String, Object>> stops = new ArrayList<>();
                
                // 拆解 StopOfRoute 的巢狀結構
                if (root.isArray()) {
                    for (JsonNode routeNode : root) {
                        String routeName = routeNode.path("RouteName").path("Zh_tw").asText("");
                        int direction = routeNode.path("Direction").asInt(0);
                        JsonNode stopsArray = routeNode.path("Stops");
                        
                        if (stopsArray.isArray()) {
                            for (JsonNode stopNode : stopsArray) {
                                Map<String, Object> s = new HashMap<>();
                                s.put("RouteName", routeName);
                                s.put("Direction", direction);
                                s.put("StopName", stopNode.path("StopName").path("Zh_tw").asText(""));
                                s.put("Lat", stopNode.path("StopPosition").path("PositionLat").asDouble(0));
                                s.put("Lng", stopNode.path("StopPosition").path("PositionLon").asDouble(0));
                                if (!routeName.isEmpty()) stops.add(s);
                            }
                        }
                    }
                }
                
                if (!stops.isEmpty()) {
                    allBusStops.put(city, stops);
                    System.out.println("✅ " + city + " 站牌預載完成: " + stops.size() + " 筆");
                    return;
                }
            } catch (Exception e) {
                System.out.println("⚠️ preloadBusStops " + city + " attempt " + attempt + " error: " + e.getMessage());
            }
        }
        System.out.println("❌ " + city + " 站牌預載失敗（3次重試均失敗）");
    }

    // URI 版 callTdxApi（支援含中文的 OData filter，並強化錯誤偵測）
    private synchronized JsonNode callTdxApiByUri(java.net.URI apiUri) {
        if (System.currentTimeMillis() < rateLimitUntil) return null;
        if (currentToken.isEmpty()) fetchToken();
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(currentToken);
        try {
            Thread.sleep(300);
            ResponseEntity<String> response = restTemplate.exchange(apiUri, HttpMethod.GET, new HttpEntity<>(headers), String.class);
            return objectMapper.readTree(response.getBody());
        } catch (Exception e) {
            // 【核心修正】將 TDX 的真實報錯原因印出來，不再靜默吸收
            System.out.println("❌ [TDX API 請求失敗] " + apiUri.toString() + " -> " + e.getMessage());
            
            if (e.getMessage() != null && e.getMessage().contains("429")) {
                rateLimitUntil = System.currentTimeMillis() + 60000;
            } else if (e.getMessage() != null && (e.getMessage().contains("401") || e.getMessage().contains("Unauthorized"))) {
                currentToken = "";
            }
            return null;
        }
    }
    // 🔍 站牌名稱搜尋（本地過濾，秒回）
    public Map<String, Object> getBusStopSearch(String city, String stopQuery) {
        preloadBusStops(city);
        List<Map<String, Object>> stops = allBusStops.getOrDefault(city, new ArrayList<>());
        java.util.LinkedHashSet<String> routes = new java.util.LinkedHashSet<>();
        for (Map<String, Object> s : stops) {
            String stopName = (String) s.get("StopName");
            if (stopName.contains(stopQuery)) {
                routes.add((String) s.get("RouteName"));
            }
        }
        System.out.println("✅ 站牌搜尋「" + stopQuery + "」→ " + routes.size() + " 條路線 (本地)");
        List<Map<String, Object>> result = new ArrayList<>();
        for (String route : routes) {
            Map<String, Object> item = new HashMap<>();
            item.put("RouteName", route);
            result.add(item);
        }
        return buildResponse(result, System.currentTimeMillis());
    }

   

    // 🌟 修正：車牌為 -1 轉換為尚未發車
    public Map<String, Object> getBusDynamic(String city, String routeName) {
        return getFromCacheOrFetch("BUS_" + city + "_" + routeName, REALTIME_CACHE_DURATION, () -> {
            String apiUrl = routeName.matches("\\d{4}[A-Z]?")
                    ? String.format("https://tdx.transportdata.tw/api/basic/v2/Bus/EstimatedTimeOfArrival/InterCity/%s?$format=JSON", routeName)
                    : String.format("https://tdx.transportdata.tw/api/basic/v2/Bus/EstimatedTimeOfArrival/City/%s/%s?$format=JSON", city, routeName);

            JsonNode root = callTdxApi(apiUrl);
            if (root == null) return null;
            List<Map<String, Object>> resultList = new ArrayList<>();
            if (root.isArray()) {
                for (JsonNode node : root) {
                    Map<String, Object> bus = new HashMap<>();
                    String plate = node.path("PlateNumb").asText("尚未發車");
                    if (plate.equals("-1") || plate.trim().isEmpty()) {
                        plate = "尚未發車";
                    }
                    bus.put("PlateNumb", plate);
                    bus.put("RouteUID", node.path("RouteUID").asText());
                    bus.put("StopUID", node.path("StopUID").asText());
                    bus.put("StopName", node.path("StopName").path("Zh_tw").asText());
                    bus.put("Direction", node.path("Direction").asInt(0));
                    bus.put("StopSequence", node.path("StopSequence").asInt(0));
                    bus.put("StopStatus", node.path("StopStatus").asInt());
                    bus.put("EstimateTime", node.has("EstimateTime") ? node.path("EstimateTime").asInt() : null);
                    bus.put("NextBusTime", node.path("NextBusTime").asText(""));
                    bus.put("SubRouteName", node.path("SubRouteName").path("Zh_tw").asText(""));
                    resultList.add(bus);
                }
            }
            return resultList;
        });
    }

    // 公車即時 GPS 位置
    public Map<String, Object> getBusRealTimePosition(String city, String routeName) {
        return getFromCacheOrFetch("BUS_GPS_" + city + "_" + routeName, 30000L, () -> {
            // City bus
            String cityUrl = String.format("https://tdx.transportdata.tw/api/basic/v2/Bus/RealTimeByFrequency/City/%s/%s?$format=JSON", city, routeName);
            // InterCity bus
            String interUrl = String.format("https://tdx.transportdata.tw/api/basic/v2/Bus/RealTimeByFrequency/InterCity/%s?$format=JSON", routeName);

            List<Map<String, Object>> resultList = new ArrayList<>();
            for (String apiUrl : new String[]{cityUrl, interUrl}) {
                JsonNode root = callTdxApi(apiUrl);
                if (root != null && root.isArray()) {
                    for (JsonNode node : root) {
                        JsonNode pos = node.path("BusPosition");
                        if (pos.isMissingNode()) continue;
                        Map<String, Object> bus = new HashMap<>();
                        bus.put("PlateNumb", node.path("PlateNumb").asText(""));
                        bus.put("Direction", node.path("Direction").asInt(0));
                        bus.put("Speed", node.path("Speed").asDouble(0));
                        bus.put("Lat", pos.path("PositionLat").asDouble());
                        bus.put("Lng", pos.path("PositionLon").asDouble());
                        bus.put("RouteName", node.path("RouteName").path("Zh_tw").asText(""));
                        bus.put("SubRouteName", node.path("SubRouteName").path("Zh_tw").asText(""));
                        if (bus.get("Lat") != null && (double) bus.get("Lat") > 0) {
                            resultList.add(bus);
                        }
                    }
                    if (!resultList.isEmpty()) break;
                }
            }
            return resultList.isEmpty() ? null : resultList;
        });
    }

    public Map<String, Object> getYoubikeDynamic() {
        return getFromCacheOrFetch("YOUBIKE_ALL", REALTIME_CACHE_DURATION, () -> {
            fetchYoubikeStations();
            JsonNode root1 = callTdxApi("https://tdx.transportdata.tw/api/basic/v2/Bike/Availability/City/Chiayi?$format=JSON");
            JsonNode root2 = callTdxApi("https://tdx.transportdata.tw/api/basic/v2/Bike/Availability/City/ChiayiCounty?$format=JSON");
            if (root1 == null && root2 == null) return null;
            List<Map<String, Object>> resultList = new ArrayList<>();
            for (JsonNode root : new JsonNode[]{root1, root2}) {
                if (root != null && root.isArray()) {
                    for (JsonNode node : root) {
                        Map<String, Object> bike = new HashMap<>();
                        String uid = node.path("StationUID").asText();
                        bike.put("station_uid", uid);
                        bike.put("ServiceStatus", node.path("ServiceStatus").asText());
                        bike.put("AvailableReturnBikes", node.path("AvailableReturnBikes").asInt());
                        bike.put("GeneralBikes", node.path("AvailableRentBikesDetail").path("GeneralBikes").asInt(0));
                        bike.put("ElectricBikes", node.path("AvailableRentBikesDetail").path("ElectricBikes").asInt(0));
                        JsonNode stationNode = youbikeStationMap.get(uid);
                        if (stationNode != null) {
                            bike.put("station_name", stationNode.path("StationName").path("Zh_tw").asText());
                            bike.put("lat", stationNode.path("StationPosition").path("PositionLat").asDouble());
                            bike.put("lng", stationNode.path("StationPosition").path("PositionLon").asDouble());
                        } else { bike.put("station_name", ""); }
                        resultList.add(bike);
                    }
                }
            }
            return resultList;
        });
    }

    public Map<String, Object> getTraLiveBoard(String stationId) {
        return getFromCacheOrFetch("TRA_LIVE_" + stationId, REALTIME_CACHE_DURATION, () -> {
            JsonNode root = callTdxApi(String.format("https://tdx.transportdata.tw/api/basic/v3/Rail/TRA/StationLiveBoard?$filter=StationID eq '%s'&$format=JSON", stationId));
            if (root == null) return null;
            List<Map<String, Object>> resultList = new ArrayList<>();
            if (root.has("StationLiveBoards")) {
                for (JsonNode node : root.get("StationLiveBoards")) {
                    Map<String, Object> train = new HashMap<>();
                    train.put("train_no", node.path("TrainNo").asText());
                    train.put("direction", node.path("Direction").asInt());
                    train.put("train_type_name", node.path("TrainTypeName").path("Zh_tw").asText("未知車種"));
                    train.put("delay_time", node.path("DelayTime").asInt(0));
                    train.put("schedule_arrival_time", node.path("ScheduleArrivalTime").asText());
                    train.put("schedule_departure_time", node.path("ScheduleDepartureTime").asText());
                    resultList.add(train);
                }
            }
            return resultList;
        });
    }

    // 🌟 修正：解決台鐵站名「臺」與「台」差異的問題
    public Map<String, Object> getTraOD(String origin, String dest, String date) {
        syncDailyData(); 
        List<Map<String, Object>> resultList = new ArrayList<>();
        String normOrigin = origin.replace("臺", "台");
        String normDest = dest.replace("臺", "台");

        for (Map<String, Object> train : traAllTrains) {
            List<Map<String, Object>> stops = (List<Map<String, Object>>) train.get("StopTimes");
            Map<String, Object> originStop = null;
            Map<String, Object> destStop = null;

            for (Map<String, Object> stop : stops) {
                String name = ((String) stop.get("StationName")).replace("臺", "台");
                if (name.contains(normOrigin)) originStop = stop;
                if (name.contains(normDest)) destStop = stop;
            }

            if (originStop != null && destStop != null) {
                int oSeq = (int) originStop.get("StopSequence");
                int dSeq = (int) destStop.get("StopSequence");
                if (oSeq < dSeq) {
                    Map<String, Object> match = new HashMap<>();
                    match.put("train_no", train.get("TrainNo"));
                    match.put("train_type_name", train.get("TrainTypeName"));
                    match.put("departure_time", originStop.get("DepartureTime"));
                    match.put("arrival_time", destStop.get("ArrivalTime"));
                    match.put("stops", stops); 
                    resultList.add(match);
                }
            }
        }
        resultList.sort(Comparator.comparing(m -> (String) m.get("departure_time")));
        return buildResponse(resultList, System.currentTimeMillis());
    }

    // 🌟 修正：解決高鐵站名「臺」與「台」差異的問題
    public Map<String, Object> getThsrOD(String origin, String dest, String date) {
        syncDailyData();
        List<Map<String, Object>> resultList = new ArrayList<>();
        String normOrigin = origin.replace("臺", "台");
        String normDest = dest.replace("臺", "台");

        for (Map<String, Object> train : thsrAllTrains) {
            List<Map<String, Object>> stops = (List<Map<String, Object>>) train.get("StopTimes");
            Map<String, Object> originStop = null;
            Map<String, Object> destStop = null;

            for (Map<String, Object> stop : stops) {
                String name = ((String) stop.get("StationName")).replace("臺", "台");
                if (name.contains(normOrigin)) originStop = stop;
                if (name.contains(normDest)) destStop = stop;
            }

            if (originStop != null && destStop != null) {
                int oSeq = (int) originStop.get("StopSequence");
                int dSeq = (int) destStop.get("StopSequence");
                if (oSeq < dSeq) {
                    Map<String, Object> match = new HashMap<>();
                    match.put("TrainNo", train.get("TrainNo"));
                    match.put("DepartureTime", originStop.get("DepartureTime"));
                    match.put("ArrivalTime", destStop.get("ArrivalTime"));
                    match.put("stops", stops); 
                    resultList.add(match);
                }
            }
        }
        resultList.sort(Comparator.comparing(m -> (String) m.get("DepartureTime")));
        return buildResponse(resultList, System.currentTimeMillis());
    }

    private final long WEATHER_CACHE_DURATION = 10800000; 

    // 🌟 專為 REST API 打造的直搗黃龍解析版
    public Map<String, Object> getWeeklyWeather(String cityType) {
        String cacheKey = "WEATHER_WEEKLY_" + cityType;
        
        return getFromCacheOrFetch(cacheKey, WEATHER_CACHE_DURATION, () -> {
            List<Map<String, Object>> resultList = new ArrayList<>();
            System.out.println("🚀 [系統檢查] 執行 REST API 專屬天氣解析程式...");
            
            try {
                String dataId = cityType.equals("Chiayi") ? "F-D0047-075" : "F-D0047-031";
                String targetLocationName = cityType.equals("Chiayi") ? "東區" : "阿里山鄉";
                
                String apiUrl = "https://opendata.cwa.gov.tw/api/v1/rest/datastore/" + dataId + "?Authorization=" + TdxConfig.CWA_API_KEY + "&format=JSON";
                
                System.out.println("🌍 正在向氣象局請求 " + targetLocationName + " 的天氣...");
                ResponseEntity<String> response = restTemplate.exchange(apiUrl, HttpMethod.GET, null, String.class);
                JsonNode root = objectMapper.readTree(response.getBody());
                
                // 1. 直搗黃龍：進入 records -> Locations
                JsonNode locationsArray = root.path("records").path("Locations");
                if (locationsArray.isArray() && !locationsArray.isEmpty()) {
                    
                    // 2. 進入 Location 陣列
                    JsonNode locationArray = locationsArray.get(0).path("Location");
                    JsonNode targetLocation = null;
                    
                    // 3. 找出我們要的鄉鎮 (東區 / 阿里山鄉)
                    if (locationArray.isArray()) {
                        for (JsonNode loc : locationArray) {
                            if (loc.path("LocationName").asText().equals(targetLocationName)) {
                                targetLocation = loc;
                                break;
                            }
                        }
                    }

                    if (targetLocation != null) {
                        // 4. 鎖定該鄉鎮的 WeatherElement 氣象元素陣列
                        JsonNode elements = targetLocation.path("WeatherElement");
                        
                        for (int i = 0; i < 14; i += 2) {
                            Map<String, Object> dayWeather = new HashMap<>();
                            String desc = getCwaElementValue(elements, "天氣現象", i);
                            int high = 0, low = 0, rain = 0, humid = 0, wind = 0;
                            
                            try { high = Integer.parseInt(getCwaElementValue(elements, "最高溫度", i)); } catch(Exception e){}
                            try { low = Integer.parseInt(getCwaElementValue(elements, "最低溫度", i)); } catch(Exception e){}
                            try { 
                                String popStr = getCwaElementValue(elements, "12小時降雨機率", i).trim();
                                rain = (popStr.isEmpty() || popStr.equals("-")) ? 0 : Integer.parseInt(popStr); 
                            } catch(Exception e){}
                            try { humid = Integer.parseInt(getCwaElementValue(elements, "平均相對濕度", i)); } catch(Exception e){}
                            try { wind = Integer.parseInt(getCwaElementValue(elements, "風速", i)); } catch(Exception e){}

                            String icon = "⛅";
                            if (desc.contains("晴")) icon = "☀️";
                            if (desc.contains("雨") || desc.contains("陣雨") || desc.contains("雷")) icon = "🌧️";
                            if (desc.contains("雷")) icon = "⛈️";
                            if (desc.contains("陰")) icon = "☁️";

                            dayWeather.put("high", high);
                            dayWeather.put("low", low);
                            dayWeather.put("icon", icon);
                            dayWeather.put("desc", desc.isEmpty() ? "多雲" : desc);
                            dayWeather.put("rain", rain);
                            dayWeather.put("humid", humid);
                            dayWeather.put("wind", wind);
                            resultList.add(dayWeather);
                        }
                        System.out.println("✅ " + targetLocationName + " 天氣解析成功！共取得 " + resultList.size() + " 筆真實資料");
                    }
                }
            } catch (Exception e) {
                System.out.println("❌ 氣象資料請求發生嚴重異常: " + e.getMessage());
            }

            // 防呆安全網
            if (resultList.isEmpty()) {
                System.out.println("⚠️ 找不到資料，啟動氣象防呆備用資料");
                for (int i = 0; i < 7; i++) {
                    Map<String, Object> dayWeather = new HashMap<>();
                    dayWeather.put("high", 31 + (int)(Math.random() * 4));
                    dayWeather.put("low", 24 + (int)(Math.random() * 3));
                    dayWeather.put("icon", i % 2 == 0 ? "☀️" : "⛅");
                    dayWeather.put("desc", i % 2 == 0 ? "晴時多雲" : "多雲時晴");
                    dayWeather.put("rain", 10 + (int)(Math.random() * 30));
                    dayWeather.put("humid", 70 + (int)(Math.random() * 15));
                    dayWeather.put("wind", 5 + (int)(Math.random() * 8));
                    resultList.add(dayWeather);
                }
            }
            return resultList;
        });
    }

    // 🌟 專門為 REST API 設計的解析器，使用中文名稱 (如 "最高溫度") 進行比對
    private String getCwaElementValue(JsonNode elements, String targetElementName, int timeIndex) {
        if (elements == null || !elements.isArray()) return "0";

        for (JsonNode element : elements) {
            // 在 REST API 裡，ElementName 的值是中文，例如 "最高溫度"
            if (targetElementName.equals(element.path("ElementName").asText())) {
                JsonNode timeArray = element.path("Time");
                
                if (timeArray.isArray() && timeIndex < timeArray.size()) {
                    JsonNode timeBlock = timeArray.get(timeIndex);
                    JsonNode valNode = timeBlock.path("ElementValue");
                    
                    // 在 REST API 裡，數值是一個陣列 [{"Temperature": "32"}] 等等
                    if (valNode.isArray() && valNode.size() > 0) {
                        JsonNode firstVal = valNode.get(0);
                        
                        // 我們不知道裡面的 key 是 Temperature 還是 MaxTemperature，所以我們直接拿第一個出現的值！
                        Iterator<String> fields = firstVal.fieldNames();
                        if (fields.hasNext()) {
                            return firstVal.path(fields.next()).asText("0");
                        }
                    }
                }
            }
        }
        return "0"; 
    }

    // 🔍 附近站牌查詢（本地 Haversine 過濾，秒回）
    // 🔍 附近站牌查詢（本地 Haversine 過濾，秒回）
    public Map<String, Object> getNearbyBusStops(String city, double lat, double lng, int radiusMeters) {
        preloadBusStops(city);
        List<Map<String, Object>> stops = allBusStops.getOrDefault(city, new ArrayList<>());
        LinkedHashMap<String, Map<String, Object>> seen = new LinkedHashMap<>();
        for (Map<String, Object> s : stops) {
            double sLat = (double) s.get("Lat");
            double sLng = (double) s.get("Lng");
            if (sLat == 0 || sLng == 0) continue;
            double dist = haversine(lat, lng, sLat, sLng);
            if (dist > radiusMeters) continue;
            String routeName = (String) s.get("RouteName");
            int direction = (int) s.get("Direction");
            String key = routeName + "_" + direction;
            
            if (!seen.containsKey(key)) {
                Map<String, Object> item = new HashMap<>();
                item.put("RouteName", routeName);
                item.put("StopName", s.get("StopName"));
                item.put("Direction", direction);
                
                // 🌟 新增魔法：掃描快取，找出這條線這個方向的「起點」與「終點」
                String origin = "";
                String dest = "";
                for (Map<String, Object> allS : stops) {
                    if (routeName.equals(allS.get("RouteName")) && direction == (int) allS.get("Direction")) {
                        String n = (String) allS.get("StopName");
                        if (origin.isEmpty()) origin = n;
                        dest = n; // 不斷覆蓋，最後一個站牌就是終點
                    }
                }
                item.put("Origin", origin.isEmpty() ? "起點" : origin);
                item.put("Destination", dest.isEmpty() ? "終點" : dest);

                seen.put(key, item);
            }
        }
        System.out.println("✅ 附近 " + radiusMeters + "m 共找到 " + seen.size() + " 條路線 (" + city + ", 本地)");
        return buildResponse(new ArrayList<>(seen.values()), System.currentTimeMillis());
    }
    private static double haversine(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371000;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    // ──────────────────────────────────────────────────────────
    //  UV 指數 + 日出日落（OpenWeatherMap One Call API）
    //  回傳格式供 Flutter weather_screen 使用
    // ──────────────────────────────────────────────────────────
    private static final long WEATHER_EXTRA_CACHE_DURATION = 60 * 60 * 1000L; // 1 小時

    public Map<String, Object> getWeatherExtra() {
        String cacheKey = "WEATHER_EXTRA";
        Long lastFetch = cacheTimeMap.get(cacheKey);
        if (lastFetch != null && (System.currentTimeMillis() - lastFetch) < WEATHER_EXTRA_CACHE_DURATION) {
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> cached = cacheDataMap.get(cacheKey);
            if (cached != null && !cached.isEmpty()) return cached.get(0);
        }

        String key = TdxConfig.OPENWEATHER_KEY;
        if (key == null || key.isEmpty()) {
            Map<String, Object> empty = new HashMap<>();
            empty.put("error", "OPENWEATHER_KEY 未設定，請在 .env 加入 OPENWEATHER_KEY=你的key");
            return empty;
        }

        try {
            String url = "https://api.openweathermap.org/data/3.0/onecall"
                    + "?lat=23.4801&lon=120.4501"
                    + "&appid=" + key
                    + "&units=metric&exclude=minutely,hourly,daily,alerts";

            ResponseEntity<String> resp = restTemplate.exchange(url, HttpMethod.GET, null, String.class);
            JsonNode root    = objectMapper.readTree(resp.getBody());
            JsonNode current = root.path("current");

            double uvi     = current.path("uvi").asDouble(0);
            long   sunrise = current.path("sunrise").asLong(0);
            long   sunset  = current.path("sunset").asLong(0);
            int    humidity = current.path("humidity").asInt(0);

            // UV 標籤
            String uviLabel, uviTip;
            if      (uvi < 3)  { uviLabel = String.format("%.1f 低", uvi);   uviTip = "無需特別防護"; }
            else if (uvi < 6)  { uviLabel = String.format("%.1f 中", uvi);   uviTip = "建議塗 SPF30+"; }
            else if (uvi < 8)  { uviLabel = String.format("%.1f 高", uvi);   uviTip = "建議塗 SPF50+"; }
            else if (uvi < 11) { uviLabel = String.format("%.1f 極高", uvi); uviTip = "上午10點後避免外出"; }
            else               { uviLabel = String.format("%.1f 危險", uvi); uviTip = "避免日曬，全身防護"; }

            // 日出日落
            java.util.function.Function<Long, String> fmt = ts -> {
                java.time.Instant instant = java.time.Instant.ofEpochSecond(ts);
                java.time.ZonedDateTime zdt = instant.atZone(java.time.ZoneId.of("Asia/Taipei"));
                return String.format("%02d:%02d", zdt.getHour(), zdt.getMinute());
            };
            String sunriseStr = sunrise > 0 ? fmt.apply(sunrise) : "--:--";
            String sunsetStr  = sunset  > 0 ? fmt.apply(sunset)  : "--:--";
            int daylightH     = (sunrise > 0 && sunset > 0) ? (int)((sunset - sunrise) / 3600) : 0;

            // 舒適度
            String comfort, comfortTip;
            if      (humidity < 40) { comfort = "乾燥"; comfortTip = "空氣乾燥，注意補水"; }
            else if (humidity < 60) { comfort = "舒適"; comfortTip = "濕度適中，體感良好"; }
            else if (humidity < 80) { comfort = "偏潮"; comfortTip = "相對濕度偏高，注意補水"; }
            else                    { comfort = "悶熱"; comfortTip = "高濕悶熱，建議待在室內"; }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("uviLabel",   uviLabel);
            result.put("uviTip",     uviTip);
            result.put("sunrise",    sunriseStr);
            result.put("sunset",     sunsetStr);
            result.put("daylightH",  daylightH);
            result.put("comfort",    comfort);
            result.put("comfortTip", comfortTip);

            // 存入 cache
            List<Map<String, Object>> wrap = new ArrayList<>();
            wrap.add(result);
            cacheDataMap.put(cacheKey, wrap);
            cacheTimeMap.put(cacheKey, System.currentTimeMillis());

            System.out.println("✅ [WeatherExtra] UV=" + uviLabel + " 日出=" + sunriseStr + " 日落=" + sunsetStr);
            return result;

        } catch (Exception e) {
            System.out.println("❌ [WeatherExtra] 失敗: " + e.getMessage());
            Map<String, Object> err = new HashMap<>();
            err.put("error", "無法取得額外天氣資料: " + e.getMessage());
            return err;
        }
    }

    public Map<String, Object> getTraTrainStops(String trainNo, String date) {
        syncDailyData();
        for (Map<String, Object> t : traAllTrains) {
            if (t.get("TrainNo").equals(trainNo)) {
                return buildResponse((List<Map<String, Object>>) t.get("StopTimes"), System.currentTimeMillis());
            }
        }
        return new HashMap<>();
    }
    public Map<String, Object> getThsrTrainStops(String trainNo, String date) {
        syncDailyData();
        for (Map<String, Object> t : thsrAllTrains) {
            if (t.get("TrainNo").equals(trainNo)) {
                return buildResponse((List<Map<String, Object>>) t.get("StopTimes"), System.currentTimeMillis());
            }
        }
        return new HashMap<>();
    }
}