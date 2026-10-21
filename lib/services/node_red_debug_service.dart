import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/node_red_connection.dart';
import 'node_red_api.dart';
import 'node_red_socket_connector.dart';

class NodeRedDebugMessage {
  const NodeRedDebugMessage({
    required this.receivedAt,
    required this.topic,
    required this.data,
  });

  final DateTime receivedAt;
  final String topic;
  final dynamic data;

  String get nodeId => data is Map ? data['id']?.toString() ?? '' : '';

  String get nodeName => data is Map ? data['name']?.toString() ?? '' : '';

  dynamic get payload {
    if (data is Map && data.containsKey('msg')) return data['msg'];
    return data;
  }
}

enum NodeRedDebugEventKind {
  connecting,
  connected,
  disconnected,
  error,
  message,
}

class NodeRedDebugEvent {
  const NodeRedDebugEvent._({required this.kind, this.message, this.error});

  const NodeRedDebugEvent.status(NodeRedDebugEventKind kind)
    : this._(kind: kind);

  const NodeRedDebugEvent.message(NodeRedDebugMessage message)
    : this._(kind: NodeRedDebugEventKind.message, message: message);

  const NodeRedDebugEvent.error(Object error)
    : this._(kind: NodeRedDebugEventKind.error, error: error);

  final NodeRedDebugEventKind kind;
  final NodeRedDebugMessage? message;
  final Object? error;
}

/// Small client for Node-RED's editor comms channel. Node-RED sends debug
/// entries as an array of `{topic, data}` objects after the `debug` topic is
/// subscribed.
class NodeRedDebugService {
  NodeRedDebugService({required this.connection, NodeRedApi? api})
    : _api = api ?? NodeRedApi();

  final NodeRedConnection connection;
  final NodeRedApi _api;
  final StreamController<NodeRedDebugEvent> _events =
      StreamController<NodeRedDebugEvent>.broadcast();
  final List<NodeRedDebugMessage> _history = <NodeRedDebugMessage>[];
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  bool _connecting = false;
  bool _subscribed = false;

  Stream<NodeRedDebugEvent> get events => _events.stream;
  List<NodeRedDebugMessage> get history => List.unmodifiable(_history);
  bool get isConnected => _channel != null && _subscribed;

  Future<void> connect() async {
    if (_disposed || _channel != null || _connecting) return;
    _connecting = true;
    _emit(const NodeRedDebugEvent.status(NodeRedDebugEventKind.connecting));
    try {
      final headers = await _api.webSocketHeaders(connection);
      final authToken = await _api.webSocketAuthToken(connection);
      final channel = connectNodeRedSocket(
        _api.webSocketUri(connection),
        headers,
      );
      _channel = channel;
      await channel.ready;
      if (_disposed) {
        clearConnection();
        return;
      }
      _subscription = channel.stream.listen(
        _handleFrame,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
      // A gateway authenticates the upstream Node-RED connection itself. A
      // direct connection follows the same auth message exchange as the web
      // editor, even when the HTTP upgrade already carried a bearer token.
      if (!connection.isGateway && authToken != null) {
        _send({'auth': authToken});
      } else {
        _subscribeToDebug();
      }
    } catch (error) {
      _channel = null;
      _emit(NodeRedDebugEvent.error(error));
      _emit(const NodeRedDebugEvent.status(NodeRedDebugEventKind.disconnected));
    } finally {
      _connecting = false;
    }
  }

  void clearConnection() {
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    _subscribed = false;
    channel?.sink.close();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    clearConnection();
    await _events.close();
    await _api.dispose();
  }

  void _subscribeToDebug() {
    if (_subscribed || _channel == null) return;
    _subscribed = true;
    _send({'subscribe': 'debug'});
    _emit(const NodeRedDebugEvent.status(NodeRedDebugEventKind.connected));
  }

  void _handleFrame(dynamic frame) {
    if (frame is! String && frame is! List<int>) return;
    final text = frame is String ? frame : utf8.decode(frame as List<int>);
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is Map) {
      final auth = decoded['auth']?.toString();
      if (auth == 'ok') {
        _subscribeToDebug();
      } else if (auth == 'fail') {
        _emit(
          NodeRedDebugEvent.error(const FormatException('Node-RED 调试授权失败。')),
        );
      }
      return;
    }
    if (decoded is! List) return;
    for (final item in decoded) {
      if (item is! Map) continue;
      final topic = item['topic']?.toString() ?? '';
      if (topic != 'debug' && !topic.startsWith('debug/')) continue;
      final message = NodeRedDebugMessage(
        receivedAt: DateTime.now(),
        topic: topic,
        data: item['data'],
      );
      _history.insert(0, message);
      if (_history.length > 300) _history.removeLast();
      _emit(NodeRedDebugEvent.message(message));
    }
  }

  void _handleError(Object error) {
    _emit(NodeRedDebugEvent.error(error));
  }

  void _handleDone() {
    _channel = null;
    _subscription = null;
    _subscribed = false;
    _emit(const NodeRedDebugEvent.status(NodeRedDebugEventKind.disconnected));
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (error) {
      _emit(NodeRedDebugEvent.error(error));
    }
  }

  void _emit(NodeRedDebugEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }
}
