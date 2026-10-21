import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/flow_bundle.dart';
import '../models/node_red_connection.dart';

class NodeRedApi {
  NodeRedApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _tokens = {};

  Uri _uri(NodeRedConnection connection, String endpoint) {
    final input = connection.baseUrl.trim();
    final withScheme = input.contains('://') ? input : 'http://$input';
    final root = Uri.parse(withScheme);
    if (!root.hasAuthority ||
        (root.scheme != 'http' && root.scheme != 'https')) {
      throw const FormatException('Enter a valid HTTP or HTTPS address.');
    }
    final prefix = root.path.replaceFirst(RegExp(r'/+$'), '');
    final path = '$prefix/$endpoint'.replaceAll(RegExp(r'/{2,}'), '/');
    return root.replace(path: path, query: '', fragment: '');
  }

  Future<String?> _authToken(NodeRedConnection connection) async {
    switch (connection.authMode) {
      case NodeRedAuthMode.none:
        return null;
      case NodeRedAuthMode.bearer:
      case NodeRedAuthMode.gateway:
        final token = connection.bearerToken.trim();
        if (token.isEmpty) {
          throw FormatException(
            connection.isGateway
                ? '缺少网关设备授权。请重新配对此设备。'
                : 'Enter a bearer token.',
          );
        }
        return token;
      case NodeRedAuthMode.credentials:
        if (connection.username.isEmpty || connection.password.isEmpty) {
          throw const FormatException(
            'Enter the Node-RED username and password.',
          );
        }
        final cached = _tokens[connection.id];
        if (cached != null) return cached;
        final response = await _client
            .post(
              _uri(connection, 'auth/token'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'client_id': 'node-red-admin',
                'grant_type': 'password',
                'scope': '*',
                'username': connection.username,
                'password': connection.password,
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw NodeRedApiException(
            response.statusCode == 401 || response.statusCode == 403
                ? '登录失败，请检查账号和密码。'
                : '获取访问令牌失败（HTTP ${response.statusCode}）。',
            statusCode: response.statusCode,
          );
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final token = body['access_token']?.toString();
        if (token == null || token.isEmpty) {
          throw const FormatException(
            'Node-RED did not return an access token.',
          );
        }
        _tokens[connection.id] = token;
        return token;
    }
  }

  Future<Map<String, String>> _headers(NodeRedConnection connection) async {
    final token = await _authToken(connection);
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Node-RED-API-Version': 'v2',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<FlowBundle> getFlows(NodeRedConnection connection) async {
    final headers = await _headers(connection);
    var response = await _client
        .get(_uri(connection, 'flows'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 400 || response.statusCode == 415) {
      headers.remove('Node-RED-API-Version');
      response = await _client
          .get(_uri(connection, 'flows'), headers: headers)
          .timeout(const Duration(seconds: 20));
    }
    if (response.statusCode == 401 &&
        connection.authMode == NodeRedAuthMode.credentials) {
      _tokens.remove(connection.id);
      final refreshed = await _headers(connection);
      response = await _client
          .get(_uri(connection, 'flows'), headers: refreshed)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 400 || response.statusCode == 415) {
        refreshed.remove('Node-RED-API-Version');
        response = await _client
            .get(_uri(connection, 'flows'), headers: refreshed)
            .timeout(const Duration(seconds: 20));
      }
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      _tokens.remove(connection.id);
      throw NodeRedApiException(
        '无权读取流程，请确认账号具有 flows.read 权限。',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw NodeRedApiException(
        '读取流程失败（HTTP ${response.statusCode}）。请检查实例地址和 Admin API 路径。',
        statusCode: response.statusCode,
      );
    }
    try {
      return FlowBundle.fromResponse(jsonDecode(response.body));
    } on FormatException {
      throw const NodeRedApiException('Node-RED 返回了无法识别的流程格式。');
    }
  }

  Future<FlowBundle> deploy(
    NodeRedConnection connection,
    FlowBundle draft, {
    required List<FlowNode> baseline,
  }) async {
    if (!draft.apiV2) {
      final current = await getFlows(connection);
      if (current.canonicalJson() != jsonEncode(baseline)) {
        throw const FlowConflictException();
      }
    }
    final headers = await _headers(connection);
    if (!draft.apiV2) headers.remove('Node-RED-API-Version');
    headers['Node-RED-Deployment-Type'] = 'flows';
    final body = jsonEncode(
      draft.apiV2 ? draft.toRequestBody() : draft.toLegacyBody(),
    );
    var response = await _client
        .post(_uri(connection, 'flows'), headers: headers, body: body)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 &&
        connection.authMode == NodeRedAuthMode.credentials) {
      _tokens.remove(connection.id);
      final refreshed = await _headers(connection);
      if (!draft.apiV2) refreshed.remove('Node-RED-API-Version');
      refreshed['Node-RED-Deployment-Type'] = 'flows';
      response = await _client
          .post(_uri(connection, 'flows'), headers: refreshed, body: body)
          .timeout(const Duration(seconds: 30));
    }
    if (response.statusCode == 409) throw const FlowConflictException();
    if (response.statusCode == 401 || response.statusCode == 403) {
      _tokens.remove(connection.id);
      throw NodeRedApiException(
        '部署失败：账号没有 flows.write 权限。',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw NodeRedApiException(
        '部署失败（HTTP ${response.statusCode}）。${response.body.trim()}',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 200 && response.body.isNotEmpty) {
      final payload = jsonDecode(response.body);
      if (payload is Map && payload['rev'] != null) {
        return draft.copyWith(revision: payload['rev'].toString());
      }
    }
    return getFlows(connection);
  }

  Future<void> dispose() async => _client.close();
}
