import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/node_red_connection.dart';

class ConnectionStore {
  ConnectionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _key = 'rivlen.connections.v1';
  static const _secretPrefix = 'rivlen.connection.secret.v1.';

  final FlutterSecureStorage _secureStorage;

  Future<List<NodeRedConnection>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final connections = list
          .whereType<Map>()
          .map(
            (item) =>
                NodeRedConnection.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      for (var index = 0; index < connections.length; index++) {
        var connection = connections[index];
        final savedSecrets = await _secureStorage.read(
          key: _secretKey(connection.id),
        );
        if (savedSecrets != null) {
          try {
            final decoded = jsonDecode(savedSecrets) as Map<String, dynamic>;
            connection = connection.copyWith(
              username: decoded['username'] as String? ?? '',
              password: decoded['password'] as String? ?? '',
              bearerToken: decoded['bearerToken'] as String? ?? '',
            );
          } on FormatException {
            if (_hasSecrets(connection)) await _writeSecrets(connection);
          }
        } else if (_hasSecrets(connection)) {
          await _writeSecrets(connection);
        }
        connections[index] = connection;
      }
      final sanitized = jsonEncode(
        connections.map((item) => item.toJson(includeSecrets: false)).toList(),
      );
      if (sanitized != raw) await preferences.setString(_key, sanitized);
      return connections;
    } on FormatException {
      return [];
    }
  }

  Future<void> saveAll(List<NodeRedConnection> connections) async {
    final preferences = await SharedPreferences.getInstance();
    final oldIds = _storedIds(preferences.getString(_key));
    final currentIds = connections.map((connection) => connection.id).toSet();
    for (final connection in connections) {
      if (_hasSecrets(connection)) {
        await _writeSecrets(connection);
      } else {
        await _secureStorage.delete(key: _secretKey(connection.id));
      }
    }
    await preferences.setString(
      _key,
      jsonEncode(
        connections.map((item) => item.toJson(includeSecrets: false)).toList(),
      ),
    );
    for (final removedId in oldIds.difference(currentIds)) {
      await _secureStorage.delete(key: _secretKey(removedId));
    }
  }

  bool _hasSecrets(NodeRedConnection connection) =>
      connection.username.isNotEmpty ||
      connection.password.isNotEmpty ||
      connection.bearerToken.isNotEmpty;

  String _secretKey(String id) => '$_secretPrefix$id';

  Future<void> _writeSecrets(NodeRedConnection connection) =>
      _secureStorage.write(
        key: _secretKey(connection.id),
        value: jsonEncode({
          'username': connection.username,
          'password': connection.password,
          'bearerToken': connection.bearerToken,
        }),
      );

  Set<String> _storedIds(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((item) => item['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }
}
