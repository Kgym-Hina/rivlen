import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/node_red_connection.dart';
import '../services/node_red_debug_service.dart';
import '../theme.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.connection, this.service});

  final NodeRedConnection connection;
  final NodeRedDebugService? service;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  late final NodeRedDebugService _service;
  late final bool _ownsService;
  StreamSubscription<NodeRedDebugEvent>? _subscription;
  final List<NodeRedDebugMessage> _messages = [];
  String _status = '未连接';
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service =
        widget.service ?? NodeRedDebugService(connection: widget.connection);
    _messages.addAll(_service.history);
    _subscription = _service.events.listen(_handleEvent);
    if (widget.connection.id == 'demo') {
      _status = '示例画布没有实时调试输出';
    } else {
      if (_service.isConnected) _status = '已连接';
      _service.connect();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  void _handleEvent(NodeRedDebugEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.kind) {
        case NodeRedDebugEventKind.connecting:
          _status = '正在连接';
          _error = null;
        case NodeRedDebugEventKind.connected:
          _status = '已连接';
          _error = null;
        case NodeRedDebugEventKind.disconnected:
          _status = '连接已断开';
        case NodeRedDebugEventKind.error:
          _error = _friendlyError(event.error);
          _status = '连接异常';
        case NodeRedDebugEventKind.message:
          final message = event.message;
          if (message != null) {
            _messages.insert(0, message);
            if (_messages.length > 300) _messages.removeLast();
          }
      }
    });
  }

  String _friendlyError(Object? error) {
    final text = error?.toString() ?? '无法连接到 Node-RED 调试通道';
    return text.replaceFirst('Exception: ', '');
  }

  Future<void> _reconnect() async {
    setState(() {
      _status = '正在连接';
      _error = null;
    });
    _service.clearConnection();
    await _service.connect();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status == '已连接';
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试'),
        actions: [
          IconButton(
            tooltip: '清空',
            onPressed: _messages.isEmpty
                ? null
                : () => setState(_messages.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: '重新连接',
            onPressed: widget.connection.id == 'demo' ? null : _reconnect,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusBar(isConnected),
            if (_error != null) _errorCard(_error!),
            Expanded(
              child: _messages.isEmpty
                  ? _emptyState(isConnected)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _messages.length,
                      itemBuilder: (_, index) => _messageCard(_messages[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(bool isConnected) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isConnected ? RivlenColors.green : RivlenColors.muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _status,
            style: TextStyle(color: RivlenColors.muted, fontSize: 12),
          ),
        ),
        Text(
          '${_messages.length} 条',
          style: TextStyle(color: RivlenColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _errorCard(String message) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
    decoration: BoxDecoration(
      color: RivlenColors.wine.withValues(
        alpha: RivlenColors.isDark ? 0.22 : 0.08,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: RivlenColors.wine.withValues(alpha: 0.28)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: RivlenColors.wine),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: RivlenColors.ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState(bool isConnected) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bug_report_outlined, size: 42, color: RivlenColors.muted),
          const SizedBox(height: 12),
          Text(
            isConnected ? '等待 debug 节点输出' : '连接后会在这里显示 debug 输出',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: RivlenColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在 Flow 中触发 inject 或其他节点，消息会实时出现在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(color: RivlenColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _messageCard(NodeRedDebugMessage message) {
    final payload = _formatJson(message.payload);
    final nodeLabel = message.nodeName.trim().isNotEmpty
        ? message.nodeName.trim()
        : message.nodeId.trim().isNotEmpty
        ? message.nodeId.trim()
        : 'Debug';
    final time = TimeOfDay.fromDateTime(message.receivedAt).format(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: RivlenColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RivlenColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 17,
                color: RivlenColors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nodeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: RivlenColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                time,
                style: TextStyle(color: RivlenColors.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            payload,
            style: TextStyle(
              color: RivlenColors.ink,
              fontSize: 12,
              height: 1.45,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(dynamic value) {
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value?.toString() ?? 'null';
    }
  }
}
