/// App 環境設定
///
/// API Key 不寫在程式碼裡，透過 --dart-define-from-file 在 build/run 時傳入。
///
/// 使用方式：
///   flutter run --dart-define-from-file=local.env.json
///   flutter build apk --dart-define-from-file=local.env.json
///
/// 參考 local.env.json.example 建立你自己的 local.env.json（不會被 git 追蹤）
class AppConfig {
  AppConfig._();

  /// Gemini API Key
  static const geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
}
