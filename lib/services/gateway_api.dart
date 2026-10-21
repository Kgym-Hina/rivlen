import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/gateway_pairing_file.dart';
import '../models/node_red_connection.dart';

class GatewayApi {
  GatewayApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<NodeRedConnection> pair({
    required GatewayPairingFile pairingFile,
    required String password,
    required String deviceName,
  }) async {
    final response = await _client
        .post(
          _endpoint(pairingFile.gatewayUrl, 'api/v1/pair'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'pairingFile': pairingFile.toJson(),
            'password': password,
            'deviceName': deviceName,
          }),
        )
        .timeout(const Duration(seconds: 45));
    final payload = _decodeResponse(response);
    if (response.statusCode != 201) {
      throw GatewayApiException(
        payload['error']?.toString() ?? '网关配对失败（HTTP ${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
    final device = payload['device'];
    final token = payload['accessToken']?.toString() ?? '';
    if (device is! Map<String, dynamic> || token.isEmpty) {
      throw const FormatException('网关返回了无法识别的授权信息。');
    }
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isEmpty) throw const FormatException('网关没有返回设备 ID。');
    final gatewayUrl = pairingFile.gatewayUrl.replaceFirst(RegExp(r'/+$'), '');
    final role = device['role']?.toString() ?? 'device';
    return NodeRedConnection(
      id: 'gateway-$deviceId',
      name: device['name']?.toString() ?? deviceName,
      baseUrl: '$gatewayUrl/api/node-red',
      authMode: NodeRedAuthMode.gateway,
      bearerToken: token,
      gatewayUrl: gatewayUrl,
      gatewayDeviceId: deviceId,
      gatewayRole: role,
    );
  }

  Future<GatewayDevicesSnapshot> listDevices(
    NodeRedConnection connection,
  ) async {
    _requireGateway(connection);
    final response = await _client
        .get(
          _endpoint(connection.gatewayUrl, 'api/v1/devices'),
          headers: _headers(connection),
        )
        .timeout(const Duration(seconds: 20));
    final payload = _decodeResponse(response);
    if (response.statusCode != 200) {
      throw GatewayApiException(
        payload['error']?.toString() ??
            '读取设备列表失败（HTTP ${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
    final items = payload['devices'];
    if (items is! List) throw const FormatException('网关返回的设备列表格式无效。');
    return GatewayDevicesSnapshot(
      devices: items
          .whereType<Map<String, dynamic>>()
          .map(GatewayDevice.fromJson)
          .toList(),
      currentDeviceId: payload['currentDevice']?.toString() ?? '',
      canManage: payload['canManage'] == true,
    );
  }

  Future<void> revokeDevice(
    NodeRedConnection connection,
    String deviceId,
  ) async {
    _requireGateway(connection);
    final response = await _client
        .delete(
          _endpoint(
            connection.gatewayUrl,
            'api/v1/devices/${Uri.encodeComponent(deviceId)}',
          ),
          headers: _headers(connection),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 204) {
      final payload = _decodeResponse(response);
      throw GatewayApiException(
        payload['error']?.toString() ??
            '撤销设备授权失败（HTTP ${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
  }

  void _requireGateway(NodeRedConnection connection) {
    if (!connection.isGateway || connection.gatewayUrl.isEmpty) {
      throw const FormatException('此连接不是 Rivlen Gateway。');
    }
    if (connection.bearerToken.isEmpty) {
      throw const FormatException('缺少网关设备授权。请重新配对此设备。');
    }
  }

  Map<String, String> _headers(NodeRedConnection connection) => {
    'Accept': 'application/json',
    'Authorization': 'Bearer ${connection.bearerToken}',
  };

  Uri _endpoint(String base, String path) {
    final input = base.trim();
    final withScheme = input.contains('://') ? input : 'http://$input';
    final root = Uri.parse(withScheme);
    if (!root.hasAuthority ||
        !{'http', 'https'}.contains(root.scheme) ||
        root.userInfo.isNotEmpty ||
        root.hasQuery ||
        root.hasFragment) {
      throw const FormatException('配对文件中的网关地址无效。');
    }
    final prefix = root.path.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = '$prefix/$path'.replaceAll(RegExp(r'/{2,}'), '/');
    return root.replace(path: endpoint, query: '', fragment: '');
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The caller reports a consistent API error below.
    }
    return <String, dynamic>{};
  }

  Future<void> dispose() async => _client.close();
}

class GatewayDevice {
  const GatewayDevice({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  final String id;
  final String name;
  final String role;
  final DateTime createdAt;
  final DateTime? lastAccessedAt;

  factory GatewayDevice.fromJson(Map<String, dynamic> json) => GatewayDevice(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Rivlen device',
    role: json['role']?.toString() ?? 'device',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    lastAccessedAt: DateTime.tryParse(json['lastAccessedAt']?.toString() ?? ''),
  );
}

class GatewayDevicesSnapshot {
  const GatewayDevicesSnapshot({
    required this.devices,
    required this.currentDeviceId,
    required this.canManage,
  });

  final List<GatewayDevice> devices;
  final String currentDeviceId;
  final bool canManage;
}

class GatewayApiException implements Exception {
  const GatewayApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
