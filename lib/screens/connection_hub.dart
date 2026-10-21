import 'package:flutter/material.dart';

import '../data/demo_flow.dart';
import '../models/connection_result.dart';
import '../models/flow_bundle.dart';
import '../models/node_red_connection.dart';
import '../services/connection_store.dart';
import '../services/node_red_api.dart';
import '../theme.dart';
import 'gateway_devices_screen.dart';
import 'flow_editor_screen.dart';
import 'pair_gateway_screen.dart';

class ConnectionHubScreen extends StatefulWidget {
  const ConnectionHubScreen({super.key});

  @override
  State<ConnectionHubScreen> createState() => _ConnectionHubScreenState();
}

class _ConnectionHubScreenState extends State<ConnectionHubScreen> {
  final _store = ConnectionStore();
  List<NodeRedConnection> _connections = [];
  bool _loading = true;
  String? _connectingId;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final items = await _store.load();
      if (!mounted) return;
      setState(() {
        _connections = items;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openEditor(
    NodeRedConnection connection,
    FlowBundle bundle,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            FlowEditorScreen(connection: connection, initialBundle: bundle),
      ),
    );
  }

  Future<void> _connect(NodeRedConnection connection) async {
    setState(() => _connectingId = connection.id);
    try {
      final api = NodeRedApi();
      final bundle = await api.getFlows(connection);
      await api.dispose();
      if (!mounted) return;
      setState(() => _connectingId = null);
      await _openEditor(connection, bundle);
    } catch (error) {
      if (!mounted) return;
      setState(() => _connectingId = null);
      _showError(error);
    }
  }

  Future<void> _addConnection([NodeRedConnection? initial]) async {
    ConnectionResult? result;
    if (initial == null) {
      final method = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.link_rounded),
                  title: const Text('直接连接 Node-RED'),
                  onTap: () => Navigator.pop(context, 'direct'),
                ),
                ListTile(
                  leading: Icon(Icons.qr_code_scanner_rounded),
                  title: const Text('通过网关配对'),
                  onTap: () => Navigator.pop(context, 'gateway'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || method == null) return;
      if (method == 'gateway') {
        result = await Navigator.of(context).push<ConnectionResult>(
          MaterialPageRoute(builder: (_) => const PairGatewayScreen()),
        );
      } else {
        result = await Navigator.of(context).push<ConnectionResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const ConnectionFormScreen(),
          ),
        );
      }
    } else {
      result = await Navigator.of(context).push<ConnectionResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ConnectionFormScreen(initial: initial),
        ),
      );
    }
    final completedResult = result;
    if (completedResult == null || !mounted) return;
    final updated = [..._connections];
    final index = updated.indexWhere(
      (item) => item.id == completedResult.connection.id,
    );
    if (index < 0) {
      updated.insert(0, completedResult.connection);
    } else {
      updated[index] = completedResult.connection;
    }
    await _store.saveAll(updated);
    if (!mounted) return;
    setState(() => _connections = updated);
    await _openEditor(completedResult.connection, completedResult.bundle);
  }

  Future<void> _remove(NodeRedConnection connection) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除实例？'),
        content: Text('“${connection.name}”的连接信息将从此设备移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    final updated = _connections
        .where((item) => item.id != connection.id)
        .toList();
    await _store.saveAll(updated);
    if (mounted) setState(() => _connections = updated);
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            sliver: SliverList.list(
              children: [
                const _BrandHeader(),
                const SizedBox(height: 36),
                Text(
                  '实例',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '连接自己的 Node-RED 运行环境',
                  style: TextStyle(color: RivlenColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => _addConnection(),
                  icon: Icon(Icons.add_rounded),
                  label: const Text('连接新实例'),
                  style: FilledButton.styleFrom(
                    backgroundColor: RivlenColors.wine,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
                if (_loadError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '读取已保存连接失败：$_loadError',
                    style: TextStyle(color: Color(0xFF9F3136), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 25),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_connections.isEmpty)
                  const _EmptyConnections()
                else ...[
                  Row(
                    children: [
                      Text(
                        '已保存',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: RivlenColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_connections.length}',
                        style: TextStyle(
                          color: RivlenColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._connections.map(_connectionCard),
                ],
                const SizedBox(height: 32),
                Divider(color: RivlenColors.line, height: 1),
                const SizedBox(height: 19),
                Text(
                  '画布预览',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: RivlenColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _DemoCard(
                  onTap: () => _openEditor(
                    const NodeRedConnection(
                      id: 'demo',
                      name: 'Demo flow',
                      baseUrl: '',
                      authMode: NodeRedAuthMode.none,
                    ),
                    makeDemoFlow(),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Node-RED Admin API',
                    style: TextStyle(
                      fontSize: 11,
                      color: RivlenColors.muted.withValues(alpha: 0.8),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _connectionCard(NodeRedConnection connection) {
    final isConnecting = _connectingId == connection.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: RivlenColors.surface,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: isConnecting ? null : () => _connect(connection),
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: RivlenColors.wine.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    color: RivlenColors.wine,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: RivlenColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        connection.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: RivlenColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isConnecting)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: RivlenColors.muted,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') _addConnection(connection);
                      if (value == 'remove') _remove(connection);
                      if (value == 'devices') {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                GatewayDevicesScreen(connection: connection),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      if (connection.isGateway)
                        const PopupMenuItem(
                          value: 'devices',
                          child: Text('管理授权设备'),
                        ),
                      if (!connection.isGateway)
                        const PopupMenuItem(value: 'edit', child: Text('编辑连接')),
                      const PopupMenuItem(value: 'remove', child: Text('移除实例')),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectionFormScreen extends StatefulWidget {
  const ConnectionFormScreen({super.key, this.initial});
  final NodeRedConnection? initial;

  @override
  State<ConnectionFormScreen> createState() => _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends State<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _token;
  late NodeRedAuthMode _authMode;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _url = TextEditingController(text: initial?.baseUrl ?? 'http://');
    _username = TextEditingController(text: initial?.username ?? '');
    _password = TextEditingController(text: initial?.password ?? '');
    _token = TextEditingController(text: initial?.bearerToken ?? '');
    _authMode = initial?.authMode ?? NodeRedAuthMode.none;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final connection = NodeRedConnection(
      id: widget.initial?.id ?? _createProfileId(),
      name: _name.text.trim().isEmpty ? 'Node-RED' : _name.text.trim(),
      baseUrl: _url.text.trim().replaceFirst(RegExp(r'/+$'), ''),
      authMode: _authMode,
      username: _username.text.trim(),
      password: _password.text,
      bearerToken: _token.text.trim(),
    );
    try {
      final api = NodeRedApi();
      final bundle = await api.getFlows(connection);
      await api.dispose();
      if (!mounted) return;
      Navigator.pop(context, ConnectionResult(connection, bundle));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  String _createProfileId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded),
      ),
      title: Text(widget.initial == null ? '连接实例' : '编辑连接'),
    ),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          children: [
            const _SectionHeading(
              title: 'Node-RED 地址',
              subtitle: '输入实例地址，可包含反向代理路径。',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '实例名称',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'http://192.168.1.20:1880',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              validator: (value) {
                final input = value?.trim() ?? '';
                if (input.isEmpty) return '请输入实例地址';
                final candidate = input.contains('://')
                    ? input
                    : 'http://$input';
                final uri = Uri.tryParse(candidate);
                if (uri == null ||
                    !uri.hasAuthority ||
                    !{'http', 'https'}.contains(uri.scheme)) {
                  return '请输入有效的 HTTP 或 HTTPS 地址';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeading(
              title: '身份验证',
              subtitle: '从 Node-RED Admin API 交换访问令牌。',
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: RivlenColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RivlenColors.line),
              ),
              child: Column(
                children: [
                  _AuthChoice(
                    title: '无身份验证',
                    subtitle: '适用于未启用 adminAuth 的实例',
                    selected: _authMode == NodeRedAuthMode.none,
                    onTap: () =>
                        setState(() => _authMode = NodeRedAuthMode.none),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  _AuthChoice(
                    title: '用户名和密码',
                    subtitle: '使用 Node-RED 登录凭证',
                    selected: _authMode == NodeRedAuthMode.credentials,
                    onTap: () =>
                        setState(() => _authMode = NodeRedAuthMode.credentials),
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  _AuthChoice(
                    title: 'Bearer Token',
                    subtitle: '粘贴已有 Admin API 令牌',
                    selected: _authMode == NodeRedAuthMode.bearer,
                    onTap: () =>
                        setState(() => _authMode = NodeRedAuthMode.bearer),
                  ),
                ],
              ),
            ),
            if (_authMode == NodeRedAuthMode.credentials) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) =>
                    _authMode == NodeRedAuthMode.credentials &&
                        (value?.trim().isEmpty ?? true)
                    ? '请输入用户名'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _connect(),
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    _authMode == NodeRedAuthMode.credentials &&
                        (value?.isEmpty ?? true)
                    ? '请输入密码'
                    : null,
              ),
            ],
            if (_authMode == NodeRedAuthMode.bearer) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _token,
                obscureText: !_showPassword,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '访问令牌',
                  prefixIcon: Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    _authMode == NodeRedAuthMode.bearer &&
                        (value?.trim().isEmpty ?? true)
                    ? '请输入访问令牌'
                    : null,
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _connect,
              style: FilledButton.styleFrom(
                backgroundColor: RivlenColors.wine,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('连接并读取 Flow'),
            ),
            const SizedBox(height: 11),
            Text(
              '连接使用 Node-RED Admin API。账号需要 flows.read 权限；部署还需要 flows.write。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: RivlenColors.muted.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const RivlenMark(size: 38),
      const SizedBox(width: 11),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rivlen',
            style: TextStyle(
              color: RivlenColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'FLOW EDITOR',
            style: TextStyle(
              color: RivlenColors.muted.withValues(alpha: 0.9),
              fontSize: 9,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const Spacer(),
      const RivlenThemeButton(),
    ],
  );
}

class RivlenMark extends StatelessWidget {
  const RivlenMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _RivlenMarkPainter()),
  );
}

class _RivlenMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.29),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFFFF8F5));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.095
      ..shader = const LinearGradient(
        colors: [RivlenColors.wine, RivlenColors.coral],
      ).createShader(rect);
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.3)
      ..cubicTo(
        size.width * 0.55,
        size.height * 0.28,
        size.width * 0.36,
        size.height * 0.68,
        size.width * 0.76,
        size.height * 0.7,
      );
    canvas.drawPath(path, line);
    final point = Paint()..color = RivlenColors.wine;
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.3),
      size.width * 0.12,
      point,
    );
    canvas.drawCircle(
      Offset(size.width * 0.76, size.height * 0.7),
      size.width * 0.12,
      Paint()..color = RivlenColors.coral,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
    decoration: BoxDecoration(
      color: RivlenColors.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: RivlenColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: RivlenColors.canvas,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.device_hub_outlined, color: RivlenColors.muted),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '还没有连接实例',
                style: TextStyle(
                  fontSize: 14,
                  color: RivlenColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '添加地址和登录方式后读取 Flow',
                style: TextStyle(fontSize: 12, color: RivlenColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: RivlenColors.surface,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 54,
              child: CustomPaint(painter: _DemoFlowPainter()),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '打开示例画布',
                    style: TextStyle(
                      color: RivlenColors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '查看常用节点与连线操作',
                    style: TextStyle(fontSize: 12, color: RivlenColors.muted),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: RivlenColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DemoFlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = RivlenColors.wine.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(8, size.height * 0.5),
      Offset(size.width - 8, size.height * 0.5),
      line,
    );
    for (final entry in [
      (Offset(8, size.height * 0.5), RivlenColors.amber),
      (Offset(size.width * 0.5, size.height * 0.5), RivlenColors.blue),
      (Offset(size.width - 8, size.height * 0.5), RivlenColors.green),
    ]) {
      canvas.drawCircle(entry.$1, 6, Paint()..color = RivlenColors.surface);
      canvas.drawCircle(
        entry.$1,
        4,
        Paint()
          ..color = entry.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: RivlenColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(color: RivlenColors.muted, fontSize: 12)),
    ],
  );
}

class _AuthChoice extends StatelessWidget {
  const _AuthChoice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: RivlenColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: RivlenColors.muted),
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? RivlenColors.wine : RivlenColors.muted,
            size: 20,
          ),
        ],
      ),
    ),
  );
}
