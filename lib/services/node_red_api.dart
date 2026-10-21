import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/flow_bundle.dart';
import '../models/node_red_connection.dart';

class NodeRedApi {
  NodeRedApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _tokens = {};
  final Map<String, Future<Map<String, Map<String, String>>>>
  _fieldLabelRequests = {};

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

  /// Reads the form labels that Node-RED's own editor uses for the node
  /// types currently present in a flow. The endpoint is part of the editor
  /// runtime rather than the flow admin API, so an unavailable metadata
  /// response must not prevent the flow itself from opening.
  Future<Map<String, Map<String, String>>> getNodeFieldLabels(
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
    final existing = _fieldLabelRequests[requestKey];
    if (existing != null) return existing;
    final request = _loadNodeFieldLabels(connection, types);
    _fieldLabelRequests[requestKey] = request;
    request.then<void>(
      (_) => _fieldLabelRequests.remove(requestKey),
      onError: (Object error, StackTrace stackTrace) {
        _fieldLabelRequests.remove(requestKey);
      },
    );
    return request;
  }

  Future<Map<String, Map<String, String>>> _loadNodeFieldLabels(
    NodeRedConnection connection,
    List<String> requestedTypes,
  ) async {
    final headers = await _headers(connection);
    headers['Accept'] = 'application/json';
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    final nodeResponse = await _client
        .get(_uri(connection, 'nodes'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (nodeResponse.statusCode != 200) return const {};

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
    final labels = <String, Map<String, String>>{};
    for (final result in results) {
      labels.addAll(result);
    }
    return labels;
  }

  Future<Map<String, Map<String, String>>> _loadNodeSetLabels(
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
      return _parseNodeEditorLabels(response.body, set.types, locale);
    } catch (_) {
      return const {};
    }
  }

  Map<String, Map<String, String>> _parseNodeEditorLabels(
    String html,
    Set<String> expectedTypes,
    Map<String, String> locale,
  ) {
    final result = <String, Map<String, String>>{};
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
      if (fields.isNotEmpty) result[type] = fields;
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

  String _humanizeEditorKey(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();

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
