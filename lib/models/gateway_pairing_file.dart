import 'dart:convert';
import 'dart:io';

class GatewayPairingFile {
  const GatewayPairingFile({
    required this.version,
    required this.gatewayId,
    required this.gatewayUrl,
    required this.inviteId,
    required this.expiresAt,
  });

  final int version;
  final String gatewayId;
  final String gatewayUrl;
  final String inviteId;
  final DateTime expiresAt;

  factory GatewayPairingFile.decode(String raw) {
    if (raw.length > 4096) {
      throw const FormatException('配对文件过大。');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配对文件格式无效。');
    }
    final file = GatewayPairingFile(
      version: decoded['version'] is int ? decoded['version'] as int : 0,
      gatewayId: decoded['gatewayId']?.toString() ?? '',
      gatewayUrl: decoded['gatewayUrl']?.toString() ?? '',
      inviteId: decoded['inviteId']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(decoded['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
    final uri = Uri.tryParse(file.gatewayUrl);
    if (file.version != 1 ||
        file.gatewayId.isEmpty ||
        file.inviteId.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('配对文件缺少有效的网关信息。');
    }
    if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
      throw const FormatException('公网配对地址必须使用 HTTPS。');
    }
    if (file.expiresAt.isBefore(DateTime.now())) {
      throw const FormatException('配对文件已过期，请在网关上重新生成。');
    }
    return file;
  }

  static bool _isPrivateHost(String host) {
    if (host.toLowerCase() == 'localhost' ||
        host.toLowerCase().endsWith('.local')) {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (bytes.length != 4) {
      return bytes.length == 16 &&
          ((bytes.first & 0xfe) == 0xfc ||
              (bytes.first == 0xfe && (bytes[1] & 0xc0) == 0x80));
    }
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'gatewayId': gatewayId,
    'gatewayUrl': gatewayUrl,
    'inviteId': inviteId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}
