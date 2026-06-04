/// App 環境設定
///
/// API Key 不寫在程式碼裡，透過 --dart-define-from-file 在 build/run 時傳入。
///
/// 使用方式：
///   flutter run --dart-define-from-file=local.env.json
///   flutter build apk --dart-define-from-file=local.env.json
///
/// local.env.json 範例（不要提交到 git）：
/// {
///   "GEMINI_API_KEY":     "你的 Gemini API Key",
///   "OPENWEATHER_KEY":    "你的 OpenWeatherMap API Key"
/// }
///
/// OpenWeatherMap API Key 申請：
///   1. 前往 https://openweathermap.org/api
///   2. 免費註冊帳號
///   3. 前往 My API Keys → 複製預設 key
///   4. 啟用 "One Call API 3.0"（免費方案每日 1000 次）
///   5. 將 key 填入 local.env.json 的 OPENWEATHER_KEY
class AppConfig {
  AppConfig._();

  /// Gemini API Key（AI 規劃師用）
  static const geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// OpenWeatherMap API Key（UV 指數、日出日落用）
  /// 申請：https://openweathermap.org/api → 免費方案
  static const openWeatherKey = String.fromEnvironment(
    'OPENWEATHER_KEY',
    defaultValue: '',
  );

  /// 嘉義市座標（固定用於天氣 API）
  static const double chiayiLat = 23.4801;
  static const double chiayiLon = 120.4501;
}
