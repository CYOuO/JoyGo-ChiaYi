import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// AWS S3 上傳服務（Signature V4）
class AwsS3Service {
  static final _instance = AwsS3Service._();
  factory AwsS3Service() => _instance;
  AwsS3Service._();

  final String _bucket = AppConfig.awsS3Bucket;
  final String _region = AppConfig.awsS3Region;
  final String _accessKey = AppConfig.awsAccessKeyId;
  final String _secretKey = AppConfig.awsSecretAccessKey;

  String get _host => '$_bucket.s3.$_region.amazonaws.com';

  /// 上傳 JSON 字串到 S3，回傳公開 URL
  Future<String> uploadJson({
    required String key,
    required String jsonContent,
  }) async {
    final bytes = utf8.encode(jsonContent);
    return _upload(key: key, body: Uint8List.fromList(bytes), contentType: 'application/json');
  }

  Future<String> _upload({
    required String key,
    required Uint8List body,
    required String contentType,
  }) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);

    final payloadHash = sha256.convert(body).toString();
    final headers = {
      'host': _host,
      'content-type': contentType,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'x-amz-acl': 'public-read',
    };

    final signedHeaders = (headers.keys.toList()..sort()).join(';');
    final canonicalHeaders = (headers.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}:${e.value}')
        .join('\n') + '\n';

    final canonicalRequest = [
      'PUT',
      '/${Uri.encodeComponent(key).replaceAll('%2F', '/')}',
      '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$_region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      _sha256Hex(utf8.encode(canonicalRequest) as Uint8List),
    ].join('\n');

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = _hmacSha256Hex(signingKey, stringToSign);

    final authorization =
        'AWS4-HMAC-SHA256 Credential=$_accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    final uri = Uri.https(_host, '/$key');
    final response = await http.put(
      uri,
      headers: {
        ...headers,
        'authorization': authorization,
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('S3 上傳失敗 (${response.statusCode}): ${response.body}');
    }

    return 'https://$_host/$key';
  }

  // ── Signature V4 工具 ──────────────────────────────

  String _dateStamp(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  String _amzDate(DateTime dt) =>
      '${_dateStamp(dt)}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}Z';

  String _sha256Hex(List<int> data) =>
      sha256.convert(data).toString();

  Uint8List _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(utf8.encode(data)).bytes);
  }

  String _hmacSha256Hex(List<int> key, String data) =>
      _hmacSha256(key, data).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> _deriveSigningKey(String dateStamp) {
    final kDate    = _hmacSha256(utf8.encode('AWS4$_secretKey'), dateStamp);
    final kRegion  = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, 's3');
    return _hmacSha256(kService, 'aws4_request');
  }
}
