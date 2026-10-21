import 'package:flutter/material.dart';

import '../models/node_red_connection.dart';
import '../services/gateway_api.dart';
import '../theme.dart';

class GatewayDevicesScreen extends StatefulWidget {
  const GatewayDevicesScreen({super.key, required this.connection});

  final NodeRedConnection connection;

  @override
  State<GatewayDevicesScreen> createState() => _GatewayDevicesScreenState();
}

class _GatewayDevicesScreenState extends State<GatewayDevicesScreen> {
  final _api = GatewayApi();
  GatewayDevicesSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.listDevices(widget.connection);
      if (mounted) setState(() => _snapshot = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(GatewayDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备授权？'),
        content: Text('“${device.name}”将无法再访问此网关。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销授权'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _revokingId = device.id);
    try {
      await _api.revokeDevice(widget.connection, device.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设备授权已撤销')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('授权设备'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading && _snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _snapshot == null
          ? _errorView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已授权',
                          style: TextStyle(
                            color: RivlenColors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (_snapshot != null)
                        Text(
                          '${_snapshot!.devices.length}',
                          style: TextStyle(
                            color: RivlenColors.muted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Uri.parse(widget.connection.gatewayUrl).host,
                    style: TextStyle(color: RivlenColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  if (_snapshot?.canManage == false)
                    const _InfoCard(
                      icon: Icons.visibility_outlined,
                      message: '此设备没有管理授权。请使用网关所有者设备撤销其他设备。',
                    ),
                  if (_error != null && _snapshot != null) ...[
                    _InfoCard(icon: Icons.error_outline, message: _error!),
                    const SizedBox(height: 12),
                  ],
                  for (final device
                      in _snapshot?.devices ?? const <GatewayDevice>[])
                    _deviceCard(device),
                  if (_snapshot?.devices.isEmpty ?? false)
                    const _InfoCard(
                      icon: Icons.devices_outlined,
                      message: '目前没有已授权设备。',
                    ),
                ],
              ),
            ),
    ),
  );

  Widget _deviceCard(GatewayDevice device) {
    final snapshot = _snapshot!;
    final isCurrent = device.id == snapshot.currentDeviceId;
    final isOwner = device.role == 'owner';
    final canRevoke = snapshot.canManage && !isCurrent && !isOwner;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: RivlenColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RivlenColors.line),
      ),
      padding: const EdgeInsets.fromLTRB(15, 15, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: RivlenColors.wine.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.devices_outlined,
                  size: 20,
                  color: RivlenColors.wine,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: RivlenColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isCurrent) _Badge(label: isOwner ? '本设备 · 所有者' : '本设备'),
              if (!isCurrent && isOwner) const _Badge(label: '所有者'),
            ],
          ),
          const SizedBox(height: 13),
          _DetailLine(
            label: '最近访问',
            value: _relativeTime(device.lastAccessedAt),
          ),
          const SizedBox(height: 5),
          _DetailLine(label: '添加时间', value: _absoluteTime(device.createdAt)),
          if (canRevoke) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _revokingId == device.id
                    ? null
                    : () => _revoke(device),
                icon: _revokingId == device.id
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.link_off_rounded, size: 17),
                label: const Text('撤销授权'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFAC3637),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, color: RivlenColors.muted, size: 38),
          const SizedBox(height: 12),
          Text(
            _error ?? '无法读取授权设备。',
            textAlign: TextAlign.center,
            style: TextStyle(color: RivlenColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _load,
            icon: Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );

  String _relativeTime(DateTime? value) {
    if (value == null) return '尚未访问';
    final elapsed = DateTime.now().difference(value.toLocal());
    if (elapsed.inSeconds < 60) return '刚刚';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inHours < 24) return '${elapsed.inHours} 小时前';
    return _absoluteTime(value);
  }

  String _absoluteTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 66,
        child: Text(
          label,
          style: TextStyle(color: RivlenColors.muted, fontSize: 12),
        ),
      ),
      Text(value, style: TextStyle(color: RivlenColors.ink, fontSize: 12)),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: RivlenColors.wine.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(9),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: Text(
      label,
      style: TextStyle(
        color: RivlenColors.wine,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: RivlenColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: RivlenColors.line),
    ),
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: RivlenColors.muted, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: RivlenColors.muted, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
