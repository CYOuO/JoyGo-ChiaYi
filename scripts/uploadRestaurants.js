import 'dotenv/config';
import admin from 'firebase-admin';
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);

// ─── 環境變數驗證 ────────────────────────────────────
const GOOGLE_GEO_API_KEY = process.env.GOOGLE_GEOCODING_API_KEY;
const FIREBASE_STORAGE_BUCKET = process.env.FIREBASE_STORAGE_BUCKET;

if (!GOOGLE_GEO_API_KEY) {
  console.error('❌ 缺失環境變數：GOOGLE_GEOCODING_API_KEY');
  console.error('請確保 .env 檔案中已設定此值');
  process.exit(1);
}

if (!FIREBASE_STORAGE_BUCKET) {
  console.error('❌ 缺失環境變數：FIREBASE_STORAGE_BUCKET');
  console.error('請確保 .env 檔案中已設定此值');
  process.exit(1);
}

console.log('✅ 環境變數已驗證');
console.log(`   - Google API Key: ${GOOGLE_GEO_API_KEY.substring(0, 10)}...`);
console.log(`   - Firebase Bucket: ${FIREBASE_STORAGE_BUCKET}\n`);

// 初始化 Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: FIREBASE_STORAGE_BUCKET,
});
const db = admin.firestore();

console.log('✅ Firebase Admin 已初始化\n');

// ─── 餐廳原始資料 ─────────────────────────────────────────────
const restaurants = [
  { id:'1',  name:'民主雞肉飯',            images:['r01_0','r01_1','r01_2','r01_3','r01_4','r01_5'], address:'嘉義市東區民族路149號',         time:'10:00–20:40',                        description:'嘉義開業超過40年的老店，油蔥重口味深受在地人與觀光客喜愛。送餐速度快，雖需排隊但翻桌率高。旁邊設有專屬免費汽車停車場，機車可停門口。空間較擁擠，較不適合推嬰兒車。', shortDesc:'40年老店，油蔥重口味，專屬停車場，在地人推薦。', phone:'05-216-2666', price:'$ 1-200',   rating:4.2, tags:['當地名店','停車方便','油蔥香','觀光景點','有發票'] },
  { id:'2',  name:'噴水雞肉飯-小雅旗艦店', images:['r02_0','r02_1','r02_2','r02_3','r02_4','r02_5'], address:'嘉義市東區小雅路382號',          time:'10:30–20:00',                        description:'著名觀光標誌店，店面寬敞且裝潢氣派，適合多人聚餐。雞肉飯口味較油且價格稍貴，非多數在地人首選。對面設有自家大型汽車停車場，交通與停車非常方便。',                   shortDesc:'裝潢氣派大型旗艦店，附設自家停車場，適合聚餐。', phone:'05-222-2433', price:'$$ 2-400', rating:3.5, tags:['停車方便','觀光景點','適合聚餐'] },
  { id:'3',  name:'檜町雞肉飯',            images:['r03_0','r03_1','r03_2','r03_3','r03_4','r03_5'], address:'嘉義市東區吳鳳北路101號',        time:'11:00-15:00, 17:00-20:00 (週三四公休)', description:'走日式文青風格的裝潢，環境舒適漂亮。除了傳統口味，更有獨特的「焗烤雞肉飯」與「Double 雞肉飯」。口味偏清淡。汽車可停附近付費停車場，機車位較難尋找。',         shortDesc:'日式文青風格，環境極佳，獨家焗烤雞肉飯。',       phone:'05-222-7171', price:'$ 1-200',   rating:4.5, tags:['環境舒適','傳統口味','獨特料理','文青風格','清淡系'] },
  { id:'4',  name:'阿宏師火雞肉飯-宵夜幫吳鳳店', images:['r04_0','r04_1','r04_2','r04_3','r04_4','r04_5'], address:'嘉義市東區吳鳳北路127號', time:'16:00–23:30',                        description:'阿宏師的人氣分店，營業至午夜，是嘉義宵夜的熱門選擇。雞肉絲塊頭較大，口感接近肉片。位於 in89 影城附近，人潮比總店稍少，空間寬敞不擁擠，但座位數量有限。', shortDesc:'熱門宵夜首選，雞肉塊大且油香充足，環境寬敞。',   phone:'05-227-0774', price:'$ 1-200',   rating:3.8, tags:['環境舒適','深夜營業'] },
  { id:'5',  name:'嘉義體育館姊妹火雞肉飯', images:['r05_0','r05_1','r05_2','r05_3'],               address:'嘉義市東區垂楊路1號',          time:'06:00-14:00 (週三公休)',             description:'1987年創業至今的老字號，是許多嘉義人從小吃到大的回憶。特點是雞肉絲切得比一般店家大塊且帶有明顯油香。位處騎樓，夏天無冷氣。交通方便，附近停車格多。',                shortDesc:'清晨六點開賣老店，雞肉切塊大且具油香。',         phone:'05-216-3755', price:'$ 1-200',   rating:4.0, tags:['高CP值','停車方便','老字號','早開門'] },
  { id:'6',  name:'嘉義人火雞肉飯',        images:['r06_0','r06_1','r06_2','r06_3','r06_4','r06_5'], address:'嘉義市東區垂楊路157號',         time:'05:30-14:00',                        description:'由路邊攤起家發展至店面，口味偏清淡且附有油蔥酥提味，適合不喜重鹹的客人。清晨五點半即開賣，是熱門的早餐選擇。外面大馬路汽車與機車停車皆非常便利。',             shortDesc:'清淡系老字號，外帶熱門，馬路寬敞停車便利。',     phone:'05-223-1737', price:'$ 1-200',   rating:4.0, tags:['油蔥香','老字號','早開門','清淡系'] },
  { id:'7',  name:'陳家美食火雞肉飯',      images:['r07_0','r07_1','r07_2','r07_3','r07_4','r07_5'], address:'嘉義市西區民族路633號',         time:'11:00-04:00 (週四公休)',             description:'營業時間極長至凌晨四點，是宵夜的好去處。提供多樣化的小菜品項，還可搭配自製的蒜頭辣椒提升風味。內用採拋棄式碗筷，環境較為一般。',                                       shortDesc:'凌晨四點收攤，品項多樣，提供特製蒜頭辣椒。',     phone:'05-222-2748', price:'$1-200',    rating:3.0, tags:['深夜營業','獨特料理'] },
  { id:'8',  name:'圓環火雞大王火雞肉飯',  images:['r08_0','r08_1','r08_2','r08_3','r08_4','r08_5'], address:'嘉義市東區民族路108號',         time:'10:30-21:00',                        description:'菜單豐富，包含多種便當、粥品與小菜。口味相對清淡，適合大眾。店內空間寬敞明亮，對輪椅與嬰兒車友善，但尖峰時段動線較混亂。路邊設有付費停車場。',               shortDesc:'品項多元，口味清淡，空間寬敞且無障礙友善。',     phone:'05-277-2233', price:'$1-200',    rating:3.8, tags:['環境舒適','無障礙友善'] },
  { id:'9',  name:'阿樓師火雞肉飯',        images:['r09_0','r09_1','r09_2','r09_3','r09_4','r09_5'], address:'嘉義市東區吳鳳北路102號',       time:'16:00-00:00',                        description:'嘉義晚間的代表性名店，鹹度適中，雞肉切得較細碎。開店前即有排隊人潮，內用座位少且需併桌。附近設有大型付費停車場，建議騎乘機車前往最便利。',                       shortDesc:'晚間人氣名店，翻桌快但需排隊，營業至午夜。',     phone:'05-228-2738', price:'$ 1-200',   rating:4.2, tags:['當地名店','停車方便','深夜營業'] },
  { id:'10', name:'大同火雞肉飯',          images:['r10_0','r10_1','r10_2','r10_3','r10_4','r10_5'], address:'嘉義市東區民族路113號',         time:'10:00-16:00 (週二公休)',             description:'主打加入大量油蔥酥的雞肉飯，香氣撲鼻。米飯粒粒分明，火雞肉片飯份量十足但價格稍高。每日限量供應的蛋非常熱門，想吃一定要趁早。',                                       shortDesc:'油蔥酥重愛好者首選，米飯粒粒分明，雞蛋限量。',   phone:'05-275-5005', price:'$ 1-200',   rating:4.0, tags:['油蔥香'] },
  { id:'11', name:'郭家雞肉飯-中正店',     images:['r11_0','r11_1','r11_2','r11_3','r11_4','r11_5'], address:'嘉義市西區中正路368號',         time:'09:30-20:30 (週三公休)',             description:'傳承至第四代的百年老店，位於文化路商圈周邊。口味較為傳統清淡，除了雞肉飯外，豐富的湯料也是特色。環境乾淨明亮，人潮通常比文化路總店少。',                           shortDesc:'百年老字號，環境明亮乾淨，傳統清淡口味。',       phone:'05-227-0580', price:'$ 1-200',   rating:4.0, tags:['環境舒適','傳統口味','老字號','文化路'] },
  { id:'12', name:'東門雞肉飯-新民店',     images:['r12_0','r12_1','r12_2','r12_3','r12_4','r12_5'], address:'嘉義市西區新民路846號',         time:'10:00-20:30',                        description:'位於新民路上的現代化分店，環境寬敞明亮且有冷氣。特點是不提供黃蘿蔔片，而是搭配美乃滋作為沾醬。雞肉片飯口感優於雞肉絲，鄰近多家飯店。',                           shortDesc:'環境優質冷氣涼爽，獨特美乃滋沾醬組合。',         phone:'05-286-7536', price:'$ 1-200',   rating:4.0, tags:['環境舒適','有發票'] },
  { id:'13', name:'頂軒火雞肉飯',          images:['r13_0','r13_1','r13_2','r13_3','r13_4','r13_5'], address:'嘉義市東區公明路265號',         time:'10:00-19:30 (週日公休)',             description:'口味走傳統家常風格，醬汁混合甘蔗入味，甜鹹感較明顯。店內人手較少，上菜速度稍慢但環境乾淨。最大優點是幾乎不需要排隊，是趕時間時的好選擇。',                     shortDesc:'甘蔗醬汁家常味，幾乎不需排隊的低調小店。',       phone:'05-229-2555', price:'$ 1-200',   rating:3.7, tags:['傳統口味','獨特料理'] },
  { id:'14', name:'郭家美食店 (大雅路)',   images:['r14_0','r14_1','r14_2','r14_3','r14_4','r14_5'], address:'嘉義市東區大雅路二段384號',     time:'10:00-18:30 (週一公休)',             description:'從郭家總店分家出來的店面，雞肉飯口感偏濕潤且味道適中。除了雞肉飯，其招牌「粿仔湯」也深受推薦。店前方設有停車格，汽車停放相較於市區容易許多。',               shortDesc:'郭家體系，招牌粿仔湯必點，大雅路停車方便。',     phone:'05-277-5778', price:'$ 1-200',   rating:3.9, tags:['環境舒適','停車方便'] },
  { id:'15', name:'阿宏師火雞肉飯-光華總店', images:['r15_0','r15_1','r15_2','r15_3','r15_4','r15_5'], address:'嘉義市東區光華路108號',      time:'10:30-20:00',                        description:'嘉義最具名氣的店家之一，假日總是大排長龍。雞肉片飯肉質鮮嫩，油蔥與醬汁比例絕佳。位於鬧區，汽車非常難停，建議避開用餐尖峰時段前來。',                           shortDesc:'超人氣名店，雞肉片鮮嫩誘人，建議離峰前往。',     phone:'05-223-3467', price:'$ 1-200',   rating:4.3, tags:['當地名店','油蔥香'] },
  { id:'16', name:'東門雞肉飯-和平店',     images:['r16_0','r16_1','r16_2','r16_3','r16_4','r16_5'], address:'嘉義市東區光彩街198號',         time:'05:00-20:30',                        description:'位於東市場旁的多年老店，是市場收攤後或清晨買菜族的熱門用餐點。環境乾淨且設有冷氣，會開發票。口味中規中矩，雞肉片飯比雞肉絲飯更受好評。',                         shortDesc:'鄰近東市場，環境整潔冷氣涼爽，附發票。',         phone:'05-228-2678', price:'$ 1-200',   rating:4.0, tags:['環境舒適','早開門','有發票'] },
  { id:'17', name:'興安火雞肉飯',          images:['r17_0','r17_1','r17_2','r17_3','r17_4','r17_5'], address:'嘉義市東區興美六路一號',        time:'10:30-19:30',                        description:'位於興安國小正對面，以口味適中、火雞肉質佳著稱，更會搭配自製醬瓜增加口感。環境乾淨明亮且寬敞，汽車與機車停車皆非常容易，適合家庭用餐。',                       shortDesc:'興安國小對面，自製醬瓜特色，停車極方便。',       phone:'05-216-5988', price:'$ 1-200',   rating:4.2, tags:['環境舒適','高CP值','停車方便'] },
  { id:'18', name:'和平火雞肉飯',          images:['r18_0','r18_1','r18_2','r18_3','r18_4','r18_5'], address:'嘉義市東區和平路107號',         time:'07:30-17:00',                        description:'傳統口味的代表，不主動加強烈油蔥，主要靠香氣十足的雞油帶動風味。內用空間非常擁擠且可能較悶熱，常需與人併桌。雞肉質地扎實好吃。',                               shortDesc:'傳統雞油清香派，不加強烈油蔥，老饕最愛。',       phone:'05-224-0956', price:'$ 1-200',   rating:4.2, tags:['當地名店','傳統口味','無油蔥'] },
  { id:'19', name:'簡單火雞肉飯',          images:['r19_0','r19_1','r19_2','r19_3','r19_4','r19_5'], address:'嘉義市東區大雅路二段581號',     time:'08:30-20:00 (週二公休)',             description:'雖然店名「簡單」，但味道一點都不馬虎，深受大雅路一帶在地人喜愛。價格實惠，除了雞肉飯外，豬肝小菜也以無腥味著稱。環境相對寬敞舒適。',                           shortDesc:'價格便宜實惠，味道均衡適中，豬肝必點。',         phone:'05-275-4563', price:'$ 1-200',   rating:4.2, tags:['環境舒適','高CP值','當地名店'] },
  { id:'20', name:'陽光雞肉飯',            images:['r20_0','r20_1','r20_2'],                         address:'嘉義市東區學府路300號',         time:'11:00-19:00',                        description:'位於嘉義大學蘭潭校區內，是標準的校園美食。份量充足且價格最為親民（百元以下可吃飽）。最大的優勢是校區內停車空間極大，怎麼停都有位置。',                         shortDesc:'嘉大校內隱藏版，學生價超便宜，停車首選。',       phone:'0988-689-817', price:'$ 100↓',  rating:4.0, tags:['高CP值','停車方便'] },
  { id:'21', name:'三雅火雞肉飯',          images:['r21_0','r21_1','r21_2','r21_3','r21_4','r21_5'], address:'嘉義市西區仁愛路576-1號',       time:'09:00-20:30 (週四公休)',             description:'嘉義火車站對面的50年老店，是許多人進出嘉義的第一餐。出餐速度極快且有兩層樓座位。口味中規中矩、不過於油膩，對觀光客非常友善。',                                   shortDesc:'火車站旁50年老店，出餐快不油膩，交通最便。',     phone:'05-224-2586', price:'$ 1-200',   rating:3.8, tags:['環境舒適','觀光景點','老字號','近火車站'] },
  { id:'22', name:'噴水雞肉飯-中山店',     images:['r22_0','r22_1','r22_2','r22_3','r22_4','r22_5'], address:'嘉義市西區中山路325號',         time:'10:00-21:00',                        description:'噴水雞肉飯的發源總店，位於圓環心臟地帶。空間非常狹窄擁擠，且常需併桌。身為地標店雖然名氣大，但負評也多。此區域汽車極難停車，切勿違規。',                       shortDesc:'品牌創始總店，圓環旁地標，空間狹小。',           phone:'05-222-2433', price:'$ 1-200',   rating:2.9, tags:['觀光景點'] },
  { id:'23', name:'阿宏師火雞肉飯-中埔店', images:['r23_0','r23_1','r23_2','r23_3','r23_4','r23_5'], address:'嘉義縣中埔鄉中山路五段943-5號', time:'10:30-20:00',                        description:'名店阿宏師在市郊的分店，雖然位置較偏但生意依然興隆。裝潢較新，雞油與油蔥香氣足，鹹甜度適中。停車可趁下午非用餐尖峰時段臨停路邊。',                           shortDesc:'市郊分店，裝潢新，雞肉飯香氣十足。',             phone:'05-239-6656', price:'$ 1-200',   rating:3.9, tags:['當地名店','油蔥香'] },
  { id:'24', name:'郭家雞肉飯-文化店',     images:['r24_0','r24_1','r24_2','r24_3','r24_4','r24_5'], address:'嘉義市東區文化路148號',         time:'10:00-04:00',                        description:'位於文化路夜市核心，營業至凌晨四點。不加油蔥酥但調味依然優秀，翻桌率極高，即使大排長龍通常也不用等太久。環境整潔，但此區域停車極度不便。',                     shortDesc:'夜市內指標老店，無油蔥系，營業至深夜。',         phone:'05-225-6214', price:'$ 1-200',   rating:3.4, tags:['環境舒適','深夜營業','無油蔥','文化路'] },
  { id:'25', name:'正統火雞肉飯',          images:['r25_0','r25_1','r25_2','r25_3','r25_4','r25_5'], address:'嘉義市東區大雅路二段591號',     time:'08:00-13:50, 16:30-19:30 (週一公休)', description:'Google 評價高達 4.6 顆星的神級小店。價格極其便宜且湯品物超所值，油蔥與雞肉片飯的香氣讓在地人瘋狂。缺點是位置少且停車位極難尋找。',                             shortDesc:'全嘉義評價最高店之一，CP值神級，油蔥爆香。',     phone:'05-276-2679', price:'$ 1-200',   rating:4.6, tags:['高CP值','當地名店','油蔥香'] },
  { id:'26', name:'車頭火雞肉飯',          images:['r26_0','r26_1','r26_2','r26_3','r26_4','r26_5'], address:'嘉義市西區中正路707號',         time:'10:00-20:30 (週三公休)',             description:'位在火車站對面，不僅觀光客愛，許多在地人也會吃。一、二樓皆有座位且寬敞，二樓窗邊位置還能看街景。雞肉份量給得非常大方，出餐節奏快。',                           shortDesc:'火車站前指標，二樓景觀座位，雞肉份量多。',       phone:'05-225-7793', price:'$ 1-200',   rating:4.3, tags:['環境舒適','高CP值','觀光景點','近火車站'] },
  { id:'27', name:'阿霞-二代店',           images:['r27_0','r27_1','r27_2','r27_3','r27_4','r27_5'], address:'嘉義市西區中正路479號',         time:'平日16:00-22:00, 假日11:30-21:30',  description:'名店阿霞的二代店，走文青明亮裝潢路線，環境非常乾淨舒服。火雞肉品質穩定，整體口味適中。附近有收費停車場，是逛街累了用餐的好選擇。',                             shortDesc:'質感文青裝潢，環境整潔明亮，名店二代經營。',     phone:'05-225-0323', price:'$ 1-200',   rating:4.1, tags:['環境舒適','當地名店','文青風格'] },
  { id:'28', name:'噴水雞肉飯-新民店',     images:['r28_0','r28_1','r28_2'],                         address:'嘉義市西區新民路880號',         time:'09:30-20:00',                        description:'噴水體系的大型分店，店面寬敞且停車比總店容易。雖然環境較大，但許多評價反映價格偏高且性價比與衛生條件有進步空間。適合不想排隊的臨時客。',                       shortDesc:'噴水大面積分店，不需排隊，但性價比受質疑。',     phone:'05-285-9000', price:'$ 1-200',   rating:3.3, tags:['環境舒適','性價比低'] },
  { id:'29', name:'阿德師火雞肉飯',        images:['r29_0','r29_1','r29_2','r29_3'],                 address:'嘉義市西區建成街42號',         time:'10:30-20:00 (週一公休)',             description:'隱身在巷弄內的溫馨老店，老闆親切充滿人情味。走低油健康路線，雞肉大塊且給得豪邁，還可以客製化加量。環境老舊但很有傳統味道，高評價首選。',                     shortDesc:'巷弄內的人情味老店，肉大塊豪邁，老闆超親切。',   phone:'05-286-2377', price:'$ 1-200',   rating:4.5, tags:['高CP值','傳統口味','巷弄美食'] },
  { id:'30', name:'阿信美食',              images:['r30_0','r30_1','r30_2'],                         address:'嘉義市西區中正路426號',         time:'22:00-04:30',                        description:'嘉義最知名的深夜宵夜雞肉飯之一。雖然十點才開賣，但人潮總是絡繹不絕。CP值極高，飯粒濕潤且香氣足。在深夜的嘉義街頭，這碗飯顯得格外美味。',                     shortDesc:'深夜傳奇美食，十點開賣必排隊，高CP值宵夜。',     phone:'05-229-3925', price:'$ 1-200',   rating:4.0, tags:['高CP值','深夜營業'] },
];

// ─── 工具函式 ─────────────────────────────────────────────────

/**
 * 將圖片 key（如 r01_0）轉成 Firebase Storage 公開 URL
 * 格式對應你上傳的路徑：turkey_rice_images/01minzu_0.jpg
 */
function imageKeyToFirebaseUrl(key) {
  // key 格式：r01_0 → 需要對應的檔名
  const keyMap = {
    r01: '01minzu', r02: '02pensuei', r03: '03kuaiting',
    r04: '04hong',  r05: '05sister',  r06: '06cy',
    r07: '07chen',  r08: '08king',    r09: '09lou',
    r10: '10tong',  r11: '11guoZong', r12: '12dongXin',
    r13: '13ding',  r14: '14guoDaya', r15: '15hongGuan',
    r16: '16dongHe',r17: '17xing',   r18: '18heping',
    r19: '19jianDan',r20: '20sun',   r21: '21yai',
    r22: '22penYuan',r23: '23hongZong',r24: '24guoWen',
    r25: '25zheng', r26: '26che',    r27: '27xia2',
    r28: '28penXin',r29: '29ade',    r30: '30xin',
  };
  // key 像 'r01_0'，拆成前綴 'r01' 和索引 '0'
  const match = key.match(/^(r\d+)_(\d+)$/);
  if (!match) return null;
  const [, prefix, index] = match;
  const name = keyMap[prefix];
  if (!name) return null;
  const fileName = `${name}_${index}.jpg`;
  const encoded = encodeURIComponent(`turkey_rice_images/${fileName}`);
  return `https://firebasestorage.googleapis.com/v0/b/${FIREBASE_STORAGE_BUCKET}/o/${encoded}?alt=media`;
}

/**
 * 呼叫 Google Geocoding API，回傳 { lat, lng } 或 null
 */
async function geocode(address) {
  const { default: fetch } = await import('node-fetch');
  const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${GOOGLE_GEO_API_KEY}&language=zh-TW`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.status === 'OK' && data.results.length > 0) {
    const { lat, lng } = data.results[0].geometry.location;
    return { lat, lng };
  }
  console.warn(`  ⚠️  無法取得座標：${address}（狀態：${data.status}）`);
  return null;
}

// ─── 主流程 ──────────────────────────────────────────────────
async function main() {
  console.log(`\n🚀 開始處理 ${restaurants.length} 筆餐廳資料…\n`);

  for (const r of restaurants) {
    console.log(`[${r.id.padStart(2, '0')}] ${r.name}`);

    // 1. Geocoding
    process.stdout.write(`     📍 Geocoding: ${r.address} … `);
    const coords = await geocode(r.address);
    if (coords) {
      console.log(`✅  (${coords.lat.toFixed(5)}, ${coords.lng.toFixed(5)})`);
    }

    // 2. 轉換圖片 URL
    const imageUrls = r.images.map(imageKeyToFirebaseUrl).filter(Boolean);

    // 3. 組合 Firestore 文件
    const doc = {
      id:          r.id,
      name:        r.name,
      address:     r.address,
      time:        r.time,
      description: r.description,
      shortDesc:   r.shortDesc,
      phone:       r.phone,
      price:       r.price,
      rating:      r.rating,
      tags:        r.tags,
      images:      imageUrls,
      location:    coords
        ? new admin.firestore.GeoPoint(coords.lat, coords.lng)
        : null,
      updatedAt:   admin.firestore.FieldValue.serverTimestamp(),
    };

    // 4. 寫入 Firestore（collection: restaurants，document id 用 r.id）
    try {
      await db.collection('restaurants').doc(r.id).set(doc);
      console.log(`     ☁️  已寫入 Firestore ✅`);
    } catch (err) {
      console.error(`     ❌ Firestore 寫入失敗：`, err.message);
    }

    // 避免 Geocoding API 限速（每秒最多 50 次，稍微等一下）
    await new Promise(res => setTimeout(res, 120));
  }

  console.log('\n🎉 全部完成！');
  process.exit(0);
}

main().catch(err => {
  console.error('❌ 發生錯誤：', err);
  process.exit(1);
});
