import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/flow_bundle.dart';
import '../models/home_assistant_catalog.dart';
import '../models/node_red_connection.dart';
import '../models/node_editor_schema.dart';

class NodeRedApi {
  NodeRedApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _tokens = {};
  final Map<String, Future<Map<String, NodeEditorSchema>>> _schemaRequests = {};

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
    String? token;
    try {
      token = await _authToken(connection);
    } on NodeRedApiException catch (error) {
      // Some installations put Node-RED behind a Basic-auth reverse proxy
      // and do not expose the OAuth token endpoint. Keep those connections
      // usable without weakening normal invalid-credential errors.
      if (connection.authMode != NodeRedAuthMode.credentials ||
          (error.statusCode != 400 && error.statusCode != 401)) {
        rethrow;
      }
      token = null;
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Node-RED-API-Version': 'v2',
      if (token != null) 'Authorization': 'Bearer $token',
      if (token == null && connection.authMode == NodeRedAuthMode.credentials)
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}',
    };
  }

  /// Builds the WebSocket endpoint used by Node-RED's editor comms channel.
  /// The gateway exposes the same path below `/api/node-red`.
  Uri webSocketUri(NodeRedConnection connection) {
    final httpUri = _uri(connection, 'comms');
    return httpUri.replace(scheme: httpUri.scheme == 'https' ? 'wss' : 'ws');
  }

  Future<Map<String, String>> webSocketHeaders(
    NodeRedConnection connection,
  ) async {
    try {
      final token = await _authToken(connection);
      return {if (token != null) 'Authorization': 'Bearer $token'};
    } on NodeRedApiException catch (error) {
      if (connection.authMode != NodeRedAuthMode.credentials ||
          (error.statusCode != 400 && error.statusCode != 401)) {
        rethrow;
      }
      return {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}',
      };
    }
  }

  Future<String?> webSocketAuthToken(NodeRedConnection connection) async {
    try {
      return await _authToken(connection);
    } on NodeRedApiException catch (error) {
      if (connection.authMode == NodeRedAuthMode.credentials &&
          (error.statusCode == 400 || error.statusCode == 401)) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> inject(NodeRedConnection connection, String nodeId) async {
    final endpoint = 'inject/${Uri.encodeComponent(nodeId)}';
    var headers = await _headers(connection);
    headers.remove('Node-RED-API-Version');
    var response = await _client
        .post(_uri(connection, endpoint), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 &&
        connection.authMode == NodeRedAuthMode.credentials) {
      _tokens.remove(connection.id);
      headers = await _headers(connection);
      headers.remove('Node-RED-API-Version');
      response = await _client
          .post(_uri(connection, endpoint), headers: headers)
          .timeout(const Duration(seconds: 20));
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      _tokens.remove(connection.id);
      throw NodeRedApiException(
        '无法触发节点，请确认账号具有 Node-RED 编辑权限。',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw NodeRedApiException(
        '触发节点失败（HTTP ${response.statusCode}）。${response.body.trim()}',
        statusCode: response.statusCode,
      );
    }
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

  /// Loads the dynamic Home Assistant data that Node-RED already has access
  /// to. The gateway only exposes the read-only metadata endpoints used here;
  /// the Home Assistant token therefore stays inside Node-RED.
  Future<HomeAssistantCatalog> getHomeAssistantCatalog(
    NodeRedConnection connection, {
    required Map<String, String> servers,
  }) async {
    if (servers.isEmpty) return const HomeAssistantCatalog();
    final results = await Future.wait(
      servers.entries.map((entry) async {
        final serverId = entry.key.trim();
        if (serverId.isEmpty) return const HomeAssistantCatalog();
        try {
          final resourceNames = const [
            'entities',
            'services',
            'areas',
            'devices',
            'floors',
            'labels',
          ];
          final resourceValues = await Future.wait(
            resourceNames.map(
              (resource) => _getNodeRedJson(
                connection,
                'homeassistant/$resource/${Uri.encodeComponent(serverId)}',
              ).catchError((_) => null),
            ),
          );
          return homeAssistantCatalogFromResponses(
            entitiesPayload: resourceValues[0],
            servicesPayload: resourceValues[1],
            areasPayload: resourceValues[2],
            devicesPayload: resourceValues[3],
            floorsPayload: resourceValues[4],
            labelsPayload: resourceValues[5],
            serverId: serverId,
            serverName: entry.value,
          );
        } catch (_) {
          return const HomeAssistantCatalog();
        }
      }),
    );
    var catalog = const HomeAssistantCatalog();
    for (final result in results) {
      catalog = catalog.merge(result);
    }
    return catalog;
  }

  /// Returns the installed palette types so the mobile picker can expose HA
  /// nodes that are not part of Rivlen's built-in catalog.
  Future<List<Map<String, String>>> getInstalledNodeTypes(
    NodeRedConnection connection,
  ) async {
    try {
      final response = await _client
          .get(
            _uri(connection, 'nodes'),
            headers: {
              ...await _headers(connection),
              'Accept': 'text/html, application/json;q=0.9, */*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return const [];
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        return _parseInstalledNodeTypesHtml(response.body);
      }
      if (decoded is! List) {
        return _parseInstalledNodeTypesHtml(response.body);
      }
      final result = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is! Map || item['types'] is! List) continue;
        final module = item['module']?.toString().trim() ?? '';
        final packageName = item['name']?.toString().trim() ?? '';
        for (final rawType in item['types'] as List) {
          final type = rawType.toString().trim();
          if (type.isEmpty) continue;
          result.add({'type': type, 'module': module, 'package': packageName});
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, String>> _parseInstalledNodeTypesHtml(String html) {
    final result = <Map<String, String>>[];
    final seen = <String>{};
    final markerPattern = RegExp(
      r'''<!--\s*---\s*\[red-module:([^\]]+)\]\s*---\s*-->''',
      caseSensitive: false,
    );
    final templates = RegExp(
      r'''<script\b[^>]*data-template-name\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    ).allMatches(html);
    final markers = markerPattern.allMatches(html).toList(growable: false);
    var markerIndex = 0;
    String module = '';
    for (final template in templates) {
      while (markerIndex < markers.length &&
          markers[markerIndex].start < template.start) {
        module = markers[markerIndex].group(1)?.split('/').first.trim() ?? '';
        markerIndex++;
      }
      final type = template.group(1)?.trim() ?? '';
      if (type.isEmpty || !seen.add(type)) continue;
      result.add({'type': type, 'module': module, 'package': module});
    }
    return result;
  }

  Future<dynamic> _getNodeRedJson(
    NodeRedConnection connection,
    String endpoint,
  ) async {
    final headers = await _headers(connection);
    var response = await _client
        .get(_uri(connection, endpoint), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 &&
        connection.authMode == NodeRedAuthMode.credentials) {
      _tokens.remove(connection.id);
      response = await _client
          .get(_uri(connection, endpoint), headers: await _headers(connection))
          .timeout(const Duration(seconds: 20));
    }
    if (response.statusCode != 200) {
      throw NodeRedApiException(
        '读取 Home Assistant 数据失败（HTTP ${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(response.body);
  }

  /// Reads the form schema that Node-RED's own editor uses for the node
  /// types currently present in a flow. The HTML template is the source of
  /// truth for both field labels and field order.
  Future<Map<String, NodeEditorSchema>> getNodeEditorSchemas(
    NodeRedConnection connection,
    Iterable<String> nodeTypes,
  ) {
    final types =
        nodeTypes
            .map((type) => type.trim())
            .where((type) => type.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (types.isEmpty) return Future.value(const {});
    final requestKey =
        '${connection.id}|${connection.baseUrl}|${types.join('\u001f')}';
    final existing = _schemaRequests[requestKey];
    if (existing != null) return existing;
    final request = _loadNodeEditorSchemas(connection, types);
    _schemaRequests[requestKey] = request;
    request.then<void>(
      (_) => _schemaRequests.remove(requestKey),
      onError: (Object error, StackTrace stackTrace) {
        _schemaRequests.remove(requestKey);
      },
    );
    return request;
  }

  Future<Map<String, Map<String, String>>> getNodeFieldLabels(
    NodeRedConnection connection,
    Iterable<String> nodeTypes,
  ) async {
    final schemas = await getNodeEditorSchemas(connection, nodeTypes);
    return {for (final entry in schemas.entries) entry.key: entry.value.labels};
  }

  Future<Map<String, NodeEditorSchema>> _loadNodeEditorSchemas(
    NodeRedConnection connection,
    List<String> requestedTypes,
  ) async {
    final headers = await _headers(connection);
    headers['Accept'] = 'text/html, application/json;q=0.9, */*;q=0.8';
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    final nodeResponse = await _client
        .get(_uri(connection, 'nodes'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (nodeResponse.statusCode != 200) return const {};

    final html = nodeResponse.body;
    if (html.contains('data-template-name=')) {
      return _parseNodeEditorSchemas(html, requestedTypes.toSet(), const {});
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(nodeResponse.body);
    } on FormatException {
      return const {};
    }
    if (decoded is! List) return const {};

    final wanted = requestedTypes.toSet();
    final sets = <String, _NodeSetReference>{};
    for (final value in decoded) {
      if (value is! Map) continue;
      final types = value['types'];
      final typeNames = types is List
          ? types.map((type) => type.toString()).toSet()
          : <String>{};
      if (typeNames.intersection(wanted).isEmpty) continue;
      final id = value['id']?.toString() ?? '';
      final module = value['module']?.toString().trim() ?? '';
      final slash = id.lastIndexOf('/');
      final resolvedModule = module.isNotEmpty
          ? module
          : slash > 0
          ? id.substring(0, slash)
          : '';
      final setName = value['name']?.toString().trim().isNotEmpty == true
          ? value['name'].toString().trim()
          : slash >= 0 && slash < id.length - 1
          ? id.substring(slash + 1)
          : '';
      if (resolvedModule.isEmpty || setName.isEmpty) continue;
      final key = '$resolvedModule/$setName';
      sets[key] = _NodeSetReference(
        module: resolvedModule,
        setName: setName,
        types: typeNames.intersection(wanted),
      );
    }
    if (sets.isEmpty) return const {};

    final locales = <String, Map<String, String>>{};
    final localeResults = await Future.wait(
      sets.values.map((set) async {
        try {
          final response = await _client
              .get(
                _uri(connection, 'locales/${set.module}'),
                headers: {...headers, 'Accept': 'application/json'},
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) return null;
          return (
            module: set.module,
            values: _flattenLocale(jsonDecode(response.body)),
          );
        } on FormatException {
          // A node can still provide readable literal labels without a locale.
          return null;
        } catch (_) {
          return null;
        }
      }),
    );
    for (final result in localeResults) {
      if (result != null) locales[result.module] = result.values;
    }

    final results = await Future.wait(
      sets.values.map(
        (set) => _loadNodeSetLabels(
          connection,
          set,
          locales[set.module] ?? const {},
          headers,
        ),
      ),
    );
    final labels = <String, NodeEditorSchema>{};
    for (final result in results) {
      labels.addAll(result);
    }
    return labels;
  }

  Future<Map<String, NodeEditorSchema>> _loadNodeSetLabels(
    NodeRedConnection connection,
    _NodeSetReference set,
    Map<String, String> locale,
    Map<String, String> baseHeaders,
  ) async {
    try {
      final response = await _client
          .get(
            _uri(connection, 'nodes/${set.module}/${set.setName}'),
            headers: {
              ...baseHeaders,
              'Accept': 'text/html, application/xhtml+xml;q=0.9, */*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return const {};
      }
      return _parseNodeEditorSchemas(response.body, set.types, locale);
    } catch (_) {
      return const {};
    }
  }

  Map<String, NodeEditorSchema> _parseNodeEditorSchemas(
    String html,
    Set<String> expectedTypes,
    Map<String, String> locale,
  ) {
    final result = <String, NodeEditorSchema>{};
    final templates = RegExp(
      r'''<script\b([^>]*)data-template-name\s*=\s*["']([^"']+)["'][^>]*>(.*?)</script>''',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html);
    for (final template in templates) {
      final type = template.group(2)?.trim();
      if (type == null || !expectedTypes.contains(type)) continue;
      final body = template.group(3) ?? '';
      final fields = <String, String>{};
      final fieldOrder = <String>[];
      final labels = RegExp(
        r'<label\b([^>]*)>(.*?)</label>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(body);
      for (final label in labels) {
        final attributes = label.group(1) ?? '';
        final fieldMatch = RegExp(
          r'''\bfor\s*=\s*["']node-input-([^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(attributes);
        if (fieldMatch == null) continue;
        final field = fieldMatch.group(1)?.trim();
        if (field == null || field.isEmpty) continue;
        final labelBody = label.group(2) ?? '';
        final tokens =
            RegExp(
                  r'''data-i18n\s*=\s*["']([^"']+)["']''',
                  caseSensitive: false,
                )
                .allMatches('$attributes $labelBody')
                .map((match) {
                  return _stripLocaleAttribute(match.group(1) ?? '');
                })
                .where((token) => token.isNotEmpty);
        final text = _plainHtmlText(labelBody);
        final resolved = _resolveEditorLabel(text, tokens, locale);
        if (resolved.isNotEmpty) fields[field] = resolved;
      }
      final controls = RegExp(
        r'''<(?:input|select|textarea)\b[^>]*\bid\s*=\s*["']node-input-([^"']+)["'][^>]*>''',
        caseSensitive: false,
      ).allMatches(body);
      for (final control in controls) {
        final field = control.group(1)?.trim() ?? '';
        if (field.isEmpty || !fields.containsKey(field)) continue;
        if (!fieldOrder.contains(field)) fieldOrder.add(field);
      }
      if (fields.isNotEmpty) {
        result[type] = NodeEditorSchema(labels: fields, fieldOrder: fieldOrder);
      }
    }
    return result;
  }

  String _resolveEditorLabel(
    String literal,
    Iterable<String> tokens,
    Map<String, String> locale,
  ) {
    for (final token in tokens) {
      final localized = locale[token];
      if (localized != null && localized.trim().isNotEmpty) {
        return _plainHtmlText(localized);
      }
      final suffix = token.split('.').last;
      if (literal.isEmpty && suffix.isNotEmpty) {
        return _humanizeEditorKey(suffix);
      }
    }
    return literal;
  }

  Map<String, String> _flattenLocale(dynamic value, [String prefix = '']) {
    final result = <String, String>{};
    if (value is! Map) return result;
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      final item = entry.value;
      if (item is Map) {
        result.addAll(_flattenLocale(item, fullKey));
      } else if (item is String && item.trim().isNotEmpty) {
        result[fullKey] = item;
      }
    }
    return result;
  }

  String _stripLocaleAttribute(String token) {
    final value = token.trim();
    final separator = value.lastIndexOf(']');
    return separator >= 0 ? value.substring(separator + 1).trim() : value;
  }

  String _plainHtmlText(String value) {
    final withoutTags = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeHtmlEntities(withoutTags)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  String _humanizeEditorKey(String value) {
    final text = value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  Future<void> dispose() async => _client.close();
}

class _NodeSetReference {
  const _NodeSetReference({
    required this.module,
    required this.setName,
    required this.types,
  });

  final String module;
  final String setName;
  final Set<String> types;
}
