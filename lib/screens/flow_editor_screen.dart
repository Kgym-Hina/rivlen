import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/node_catalog.dart';
import '../models/flow_bundle.dart';
import '../models/home_assistant_catalog.dart';
import '../models/node_red_connection.dart';
import '../models/node_editor_schema.dart';
import '../services/node_red_api.dart';
import '../services/node_red_debug_service.dart';
import '../theme.dart';
import '../widgets/flow_canvas.dart';
import '../widgets/home_assistant_node_editor.dart';
import 'debug_screen.dart';

bool isHomeAssistantNodeType(String type) {
  const exact = {
    'api-call-service',
    'api-current-state',
    'api-get-history',
    'api-render-template',
    'ha-api',
    'ha-device',
    'ha-get-entities',
    'poll-state',
    'server-events',
    'server-state-changed',
    'trigger-state',
  };
  return exact.contains(type) ||
      type.startsWith('ha-') ||
      type.startsWith('api-');
}

class FlowEditorScreen extends StatefulWidget {
  const FlowEditorScreen({
    super.key,
    required this.connection,
    required this.initialBundle,
  });

  final NodeRedConnection connection;
  final FlowBundle initialBundle;

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  final _canvasKey = GlobalKey<FlowCanvasState>();
  late final NodeRedApi _api;
  late final NodeRedDebugService _debugService;
  late List<FlowNode> _nodes;
  late List<FlowNode> _deployedNodes;
  late FlowBundle _bundle;
  late String _activeTabId;
  String? _selectedNodeId;
  FlowLink? _selectedLink;
  FlowBundle? _conflictRemote;
  bool _isConflict = false;
  bool _deploying = false;
  bool _allowPop = false;
  bool _draggingNode = false;
  String? _injectingNodeId;
  List<List<FlowNode>> _undoStack = [];
  List<List<FlowNode>> _redoStack = [];
  List<String> _recentTypes = [];
  List<NodeKind> _installedNodeKinds = const [];
  Map<String, NodeEditorSchema> _nodeEditorSchemas = {};
  HomeAssistantCatalog _haCatalog = const HomeAssistantCatalog();
  Future<void>? _haCatalogRequest;
  bool _haCatalogLoaded = false;

  bool get _isDemo => widget.connection.id == 'demo';
  bool get _isDirty => _canonical(_nodes) != _canonical(_deployedNodes);
  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _api = NodeRedApi();
    _debugService = NodeRedDebugService(connection: widget.connection);
    _bundle = widget.initialBundle;
    _nodes = cloneNodes(widget.initialBundle.nodes);
    _deployedNodes = cloneNodes(widget.initialBundle.nodes);
    var tabs = _tabs;
    if (tabs.isEmpty) {
      final id = createNodeId();
      _nodes.insert(0, {
        'id': id,
        'type': 'tab',
        'label': 'Flow 1',
        'disabled': false,
        'info': '',
        'env': [],
      });
      tabs = _tabs;
    }
    _activeTabId = tabs.first['id'].toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNodeFieldLabels();
      _loadInstalledNodeKinds();
      _loadHomeAssistantCatalog();
      if (!_isDemo) _debugService.connect();
    });
  }

  @override
  void dispose() {
    _debugService.dispose();
    _api.dispose();
    super.dispose();
  }

  List<FlowNode> get _tabs =>
      _nodes.where((node) => node['type'] == 'tab').toList(growable: false);

  FlowNode get _activeTab => _tabs.firstWhere(
    (tab) => tab['id'].toString() == _activeTabId,
    orElse: () =>
        _tabs.isEmpty ? {'id': _activeTabId, 'label': 'Flow'} : _tabs.first,
  );

  String _flowLabel(FlowNode tab) {
    final label = tab['label']?.toString().trim() ?? '';
    return label.isEmpty ? 'Flow' : label;
  }

  List<FlowNode> get _visibleNodes => _nodes
      .where(
        (node) =>
            node['type'] != 'tab' &&
            node['z']?.toString() == _activeTabId &&
            !isConfigurationNode(node),
      )
      .toList(growable: false);

  FlowNode? get _selectedNode {
    final id = _selectedNodeId;
    if (id == null) return null;
    for (final node in _visibleNodes) {
      if (node['id']?.toString() == id && !isJunctionNode(node)) return node;
    }
    return null;
  }

  String _canonical(List<FlowNode> nodes) => jsonEncode(nodes);

  Future<void> _loadNodeFieldLabels([Iterable<String>? types]) async {
    if (_isDemo) return;
    final requested =
        types ?? _nodes.map((node) => node['type']?.toString() ?? '');
    try {
      final schemas = await _api.getNodeEditorSchemas(
        widget.connection,
        requested,
      );
      if (!mounted || schemas.isEmpty) return;
      setState(() {
        _nodeEditorSchemas = {..._nodeEditorSchemas, ...schemas};
      });
    } catch (_) {
      // Form metadata is an enhancement. The normal editor remains usable
      // when an older Node-RED instance does not expose the editor endpoint.
    }
  }

  Future<void> _loadHomeAssistantCatalog() {
    if (_isDemo) return Future<void>.value();
    if (_haCatalogLoaded) return Future<void>.value();
    final existing = _haCatalogRequest;
    if (existing != null) return existing;
    final servers = <String, String>{};
    for (final node in _nodes) {
      if (node['type']?.toString() != 'server') continue;
      final id = node['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final name = node['name']?.toString().trim();
      servers[id] = name == null || name.isEmpty ? id : name;
    }
    if (servers.isEmpty) {
      for (final node in _nodes) {
        if (!isHomeAssistantNodeType(node['type']?.toString() ?? '')) continue;
        final id = node['server']?.toString().trim() ?? '';
        if (id.isNotEmpty) servers.putIfAbsent(id, () => id);
      }
    }
    if (servers.isEmpty) return Future<void>.value();
    final request = _api
        .getHomeAssistantCatalog(widget.connection, servers: servers)
        .then<void>((catalog) {
          _haCatalogLoaded = true;
          if (mounted) setState(() => _haCatalog = catalog);
        })
        .catchError((_) {});
    _haCatalogRequest = request;
    request.whenComplete(() => _haCatalogRequest = null);
    return request;
  }

  Future<void> _loadInstalledNodeKinds() async {
    if (_isDemo) return;
    final installed = await _api.getInstalledNodeTypes(widget.connection);
    if (!mounted || installed.isEmpty) return;
    final seen = <String>{};
    final kinds = <NodeKind>[];
    for (final item in installed) {
      final type = item['type']?.trim() ?? '';
      if (type.isEmpty ||
          !seen.add(type) ||
          nodeKinds.any((kind) => kind.type == type) ||
          isConfigurationNode({'type': type}) ||
          type.startsWith('x-tmpl-') ||
          type == 'ha_sidebar' ||
          type == 'ha_sidebar_toolbar') {
        continue;
      }
      final module = item['module']?.trim() ?? '';
      final isHa =
          module.contains('home-assistant') || isHomeAssistantNodeType(type);
      kinds.add(
        NodeKind(
          type,
          nodeTypeLabel(type),
          isHa ? 'Home Assistant' : '已安装节点',
          nodeTypeDescription(type, module.isEmpty ? type : module),
        ),
      );
    }
    kinds.sort((a, b) => a.title.compareTo(b.title));
    setState(() => _installedNodeKinds = kinds);
  }

  void _recordSnapshot() {
    _undoStack = [..._undoStack, cloneNodes(_nodes)];
    if (_undoStack.length > 80) _undoStack.removeAt(0);
    _redoStack = [];
  }

  void _commit(List<FlowNode> next) {
    _recordSnapshot();
    setState(() {
      _nodes = next;
      _selectedLink = null;
    });
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      _redoStack = [..._redoStack, cloneNodes(_nodes)];
      _nodes = _undoStack.last;
      _undoStack = _undoStack.sublist(0, _undoStack.length - 1);
      _selectedLink = null;
    });
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      _undoStack = [..._undoStack, cloneNodes(_nodes)];
      _nodes = _redoStack.last;
      _redoStack = _redoStack.sublist(0, _redoStack.length - 1);
      _selectedLink = null;
    });
  }

  void _moveNode(String id, Offset delta) {
    if (!_draggingNode) {
      _undoStack = [..._undoStack, cloneNodes(_nodes)];
      if (_undoStack.length > 80) _undoStack.removeAt(0);
      _redoStack = [];
      _draggingNode = true;
    }
    final next = cloneNodes(_nodes);
    final index = next.indexWhere((node) => node['id'].toString() == id);
    if (index < 0) return;
    final node = next[index];
    node['x'] = (((node['x'] as num?)?.toDouble() ?? 180) + delta.dx).round();
    node['y'] = (((node['y'] as num?)?.toDouble() ?? 180) + delta.dy).round();
    setState(() {
      _nodes = next;
      _selectedNodeId = id;
    });
  }

  void _endMove() {
    final id = _selectedNodeId;
    if (id != null) {
      final next = cloneNodes(_nodes);
      final node = next.firstWhere((item) => item['id'].toString() == id);
      var x = (((node['x'] as num?)?.toDouble() ?? 0) / 20).round() * 20.0;
      var y = (((node['y'] as num?)?.toDouble() ?? 0) / 20).round() * 20.0;
      if (!isJunctionNode(node)) {
        for (final peer in _visibleNodes.where(
          (item) => item['id'].toString() != id && !isJunctionNode(item),
        )) {
          final peerX = (peer['x'] as num?)?.toDouble();
          final peerY = (peer['y'] as num?)?.toDouble();
          if (peerX != null && (x - peerX).abs() < 12) x = peerX;
          if (peerY != null && (y - peerY).abs() < 12) y = peerY;
        }
      }
      node['x'] = x.round();
      node['y'] = y.round();
      setState(() => _nodes = next);
    }
    _draggingNode = false;
  }

  void _updateNode(String id, FlowNode value) {
    final next = cloneNodes(_nodes);
    final index = next.indexWhere((node) => node['id'].toString() == id);
    if (index < 0) return;
    final original = next[index];
    next[index] = {
      ...value,
      'id': original['id'],
      'type': original['type'],
      if (original['z'] != null) 'z': original['z'],
    };
    _commit(next);
  }

  void _connect(String sourceId, int outputIndex, String targetId) {
    if (sourceId == targetId) {
      _showMessage('不能把节点连到自身');
      return;
    }
    final next = cloneNodes(_nodes);
    final sourceIndex = next.indexWhere(
      (node) => node['id'].toString() == sourceId,
    );
    if (sourceIndex < 0) return;
    final source = next[sourceIndex];
    final rawWires = source['wires'];
    final wires = rawWires is List
        ? rawWires
              .map<List<dynamic>>(
                (port) => port is List ? [...port] : <dynamic>[],
              )
              .toList()
        : <List<dynamic>>[];
    while (wires.length <= outputIndex) {
      wires.add(<dynamic>[]);
    }
    if (!wires[outputIndex].any((id) => id.toString() == targetId)) {
      wires[outputIndex].add(targetId);
    }
    source['wires'] = wires;
    _commit(next);
    _showMessage('已连接');
  }

  void _deleteNode(String id) {
    final next = cloneNodes(_nodes)
      ..removeWhere((node) => node['id'].toString() == id);
    for (final node in next) {
      if (node['wires'] is List) {
        node['wires'] = (node['wires'] as List)
            .map(
              (port) => port is List
                  ? port.where((target) => target?.toString() != id).toList()
                  : <dynamic>[],
            )
            .toList();
      }
    }
    _commit(next);
    setState(() => _selectedNodeId = null);
    _showMessage('节点已删除 · 可撤销');
  }

  void _deleteLink(FlowLink link) {
    final next = cloneNodes(_nodes);
    final source = next.firstWhere(
      (node) => node['id'].toString() == link.sourceId,
      orElse: () => <String, dynamic>{},
    );
    final wires = source['wires'];
    if (wires is List &&
        link.outputIndex < wires.length &&
        wires[link.outputIndex] is List) {
      (wires[link.outputIndex] as List).removeWhere(
        (target) => target?.toString() == link.targetId,
      );
      _commit(next);
      _showMessage('连线已删除 · 可撤销');
    }
  }

  Future<void> _injectNode(String id) async {
    final node = _nodes.firstWhere(
      (item) => item['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (node.isEmpty || node['type']?.toString() != 'inject') return;
    if (_isDemo) {
      _showMessage('示例画布未连接 Node-RED');
      return;
    }
    setState(() => _injectingNodeId = id);
    try {
      await _api.inject(widget.connection, id);
      if (mounted) _showMessage('已触发 ${nodeTitle(node)}');
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _injectingNodeId = null);
    }
  }

  Future<void> _openPicker({
    required Offset worldPoint,
    String? sourceId,
    int outputIndex = 0,
    FlowLink? insertLink,
  }) async {
    final selected = await showModalBottomSheet<NodeKind>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NodePickerSheet(
        recentTypes: _recentTypes,
        additionalNodeKinds: _installedNodeKinds,
        acceptsInput: sourceId != null || insertLink != null,
        acceptsOutput: insertLink != null,
      ),
    );
    if (selected == null) return;
    _recentTypes = [
      selected.type,
      ..._recentTypes.where((type) => type != selected.type),
    ].take(5).toList();
    if (insertLink != null) {
      _insertNode(insertLink, selected.type);
    } else {
      _addNode(
        selected.type,
        worldPoint,
        sourceId: sourceId,
        outputIndex: outputIndex,
      );
    }
  }

  void _addNode(
    String type,
    Offset worldPoint, {
    String? sourceId,
    int outputIndex = 0,
  }) {
    final node = createNode(type, _activeTabId, worldPoint.dx, worldPoint.dy);
    final next = cloneNodes(_nodes)..add(node);
    if (sourceId != null) {
      final sourceIndex = next.indexWhere(
        (item) => item['id'].toString() == sourceId,
      );
      if (sourceIndex >= 0) {
        final source = next[sourceIndex];
        final wires = source['wires'] is List
            ? (source['wires'] as List)
                  .map<List<dynamic>>(
                    (port) => port is List ? [...port] : <dynamic>[],
                  )
                  .toList()
            : <List<dynamic>>[];
        while (wires.length <= outputIndex) {
          wires.add(<dynamic>[]);
        }
        wires[outputIndex].add(node['id']);
        source['wires'] = wires;
      }
    }
    _commit(next);
    setState(() => _selectedNodeId = node['id'].toString());
  }

  void _insertNode(FlowLink link, String type) {
    final node = createNode(
      type,
      _activeTabId,
      (_nodeX(link.sourceId) + _nodeX(link.targetId)) / 2,
      (_nodeY(link.sourceId) + _nodeY(link.targetId)) / 2,
    );
    node['wires'] = [
      <dynamic>[link.targetId],
    ];
    final next = cloneNodes(_nodes);
    final source = next.firstWhere(
      (item) => item['id'].toString() == link.sourceId,
    );
    final wires = source['wires'] as List;
    final targets = (wires[link.outputIndex] as List).toList();
    final targetIndex = targets.indexWhere(
      (id) => id.toString() == link.targetId,
    );
    if (targetIndex >= 0) {
      targets[targetIndex] = node['id'];
      wires[link.outputIndex] = targets;
    }
    next.add(node);
    _commit(next);
    setState(() => _selectedNodeId = node['id'].toString());
  }

  double _nodeX(String id) =>
      (_nodes.firstWhere((node) => node['id'].toString() == id)['x'] as num?)
          ?.toDouble() ??
      0;

  double _nodeY(String id) =>
      (_nodes.firstWhere((node) => node['id'].toString() == id)['y'] as num?)
          ?.toDouble() ??
      0;

  Future<void> _editNode(String id) async {
    final original = _nodes.firstWhere((node) => node['id'].toString() == id);
    if (isJunctionNode(original)) return;
    final type = original['type']?.toString() ?? '';
    if (!_isDemo && !_nodeEditorSchemas.containsKey(type)) {
      await _loadNodeFieldLabels([type])
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    if (isHomeAssistantNodeType(type)) {
      await _loadHomeAssistantCatalog().timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<FlowNode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => isHomeAssistantNodeType(type)
          ? HomeAssistantNodeEditor(
              initial: original,
              catalog: _haCatalog,
              schema: _nodeEditorSchemas[type] ?? const NodeEditorSchema(),
            )
          : _NodeEditorSheet(
              initial: original,
              schema: _nodeEditorSchemas[type] ?? const NodeEditorSchema(),
            ),
    );
    if (result != null) {
      if (result['__delete'] == true) {
        _deleteNode(id);
      } else {
        _updateNode(id, result);
      }
    }
  }

  Future<void> _selectLink(FlowLink link) async {
    setState(() {
      _selectedNodeId = null;
      _selectedLink = link;
    });
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: RivlenColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 17),
              const Text(
                '连线操作',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.add_circle_outline_rounded),
                title: const Text('在线上插入节点'),
                onTap: () => Navigator.pop(context, 'insert'),
              ),
              ListTile(
                leading: Icon(Icons.link_off_rounded),
                title: const Text('删除连线'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedLink = null);
    if (action == 'delete') _deleteLink(link);
    if (action == 'insert') {
      await _openPicker(worldPoint: Offset.zero, insertLink: link);
    }
  }

  Future<void> _showFlows() async {
    final tabs = _tabs;
    if (tabs.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RivlenColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  const Text(
                    '切换 Flow',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.pop(context, '__create'),
                    icon: Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建 Flow'),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...tabs.map((tab) {
                final id = tab['id'].toString();
                final canDelete = tabs.length > 1;
                final count = _nodes
                    .where(
                      (node) =>
                          node['z']?.toString() == id && !isJunctionNode(node),
                    )
                    .length;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                  leading: Icon(
                    id == _activeTabId
                        ? Icons.radio_button_checked
                        : Icons.circle_outlined,
                    size: 19,
                    color: id == _activeTabId
                        ? RivlenColors.wine
                        : RivlenColors.muted,
                  ),
                  title: Text(_flowLabel(tab)),
                  subtitle: Text('$count 个节点'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '重命名 Flow',
                        icon: Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => Navigator.pop(context, 'rename:$id'),
                      ),
                      IconButton(
                        tooltip: canDelete ? '删除 Flow' : '至少保留一个 Flow',
                        icon: Icon(Icons.delete_outline_rounded, size: 18),
                        onPressed: canDelete
                            ? () => Navigator.pop(context, 'delete:$id')
                            : null,
                      ),
                    ],
                  ),
                  onTap: () => Navigator.pop(context, id),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '__create') {
      await _createFlow();
      return;
    }
    if (selected.startsWith('rename:')) {
      await _renameFlow(selected.substring(7));
      return;
    }
    if (selected.startsWith('delete:')) {
      await _deleteFlow(selected.substring(7));
      return;
    }
    setState(() {
      _activeTabId = selected;
      _selectedNodeId = null;
      _selectedLink = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _canvasKey.currentState?.resetView(),
    );
  }

  Future<void> _renameFlow(String id) async {
    final tab = _nodes.firstWhere((node) => node['id'].toString() == id);
    final controller = TextEditingController(
      text: tab['label']?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flow 名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    final next = cloneNodes(_nodes);
    final target = next.firstWhere((node) => node['id'].toString() == id);
    target['label'] = value;
    _commit(next);
  }

  String _nextFlowName() {
    final names = _tabs.map(_flowLabel).toSet();
    var index = 1;
    while (names.contains('Flow $index')) {
      index++;
    }
    return 'Flow $index';
  }

  Future<void> _createFlow() async {
    final controller = TextEditingController(text: _nextFlowName());
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建 Flow'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: 'Flow 名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = value?.trim() ?? '';
    if (name.isEmpty || !mounted) return;
    final id = createNodeId();
    final next = cloneNodes(_nodes)
      ..add({
        'id': id,
        'type': 'tab',
        'label': name,
        'disabled': false,
        'info': '',
        'env': [],
      });
    _commit(next);
    setState(() {
      _activeTabId = id;
      _selectedNodeId = null;
      _selectedLink = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _canvasKey.currentState?.resetView(),
    );
  }

  Future<void> _deleteFlow(String id) async {
    final tabs = _tabs;
    if (tabs.length <= 1) {
      _showMessage('至少保留一个 Flow');
      return;
    }
    final tab = tabs.firstWhere(
      (item) => item['id'].toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (tab.isEmpty) return;
    final expectedName = _flowLabel(tab);
    final controller = TextEditingController();
    var errorText = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('删除 Flow？'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (errorText.isNotEmpty) {
                setDialogState(() => errorText = '');
              }
            },
            decoration: InputDecoration(
              labelText: '输入完整 Flow 名称',
              hintText: expectedName,
              errorText: errorText.isEmpty ? null : errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RivlenColors.wine,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (controller.text.trim() != expectedName) {
                  setDialogState(() => errorText = '名称不匹配，请完整输入 Flow 名称');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    final removedIds = _nodes
        .where(
          (node) => node['id']?.toString() == id || node['z']?.toString() == id,
        )
        .map((node) => node['id']?.toString())
        .whereType<String>()
        .toSet();
    final next = cloneNodes(_nodes)
      ..removeWhere(
        (node) => node['id']?.toString() == id || node['z']?.toString() == id,
      );
    for (final node in next) {
      final wires = node['wires'];
      if (wires is List) {
        node['wires'] = wires
            .map(
              (port) => port is List
                  ? port
                        .where(
                          (target) => !removedIds.contains(target?.toString()),
                        )
                        .toList()
                  : <dynamic>[],
            )
            .toList();
      }
    }
    final activeWasDeleted = _activeTabId == id;
    _commit(next);
    if (activeWasDeleted) {
      final remaining = next.where((node) => node['type'] == 'tab');
      final nextTab = remaining.first;
      setState(() {
        _activeTabId = nextTab['id'].toString();
        _selectedNodeId = null;
        _selectedLink = null;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _canvasKey.currentState?.resetView(),
      );
    }
    _showMessage('Flow 已删除 · 可撤销');
  }

  Future<void> _search() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = controller.text.trim().toLowerCase();
          final results = _visibleNodes.where((node) {
            if (isJunctionNode(node)) return false;
            final haystack =
                '${nodeTitle(node)} ${node['type']} ${nodeSubtitle(node)}'
                    .toLowerCase();
            return query.isEmpty || haystack.contains(query);
          }).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                18 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: rivlenSheetHeight(context, 0.72),
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: RivlenColors.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        hintText: '搜索节点',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的节点',
                                style: TextStyle(color: RivlenColors.muted),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, _) =>
                                  Divider(height: 1, indent: 54),
                              itemBuilder: (context, index) {
                                final node = results[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: _NodeGlyph(
                                    type: node['type'].toString(),
                                  ),
                                  title: Text(nodeTitle(node)),
                                  subtitle: Text(
                                    nodeSubtitle(node),
                                    maxLines: 1,
                                  ),
                                  onTap: () {
                                    final id = node['id'].toString();
                                    Navigator.pop(context);
                                    setState(() => _selectedNodeId = id);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _canvasKey.currentState?.focusNode(
                                            id,
                                          );
                                        });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
  }

  Future<void> _more() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: RivlenColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 9),
              ListTile(
                leading: Icon(Icons.add_circle_outline_rounded),
                title: const Text('添加节点'),
                onTap: () => Navigator.pop(context, 'add'),
              ),
              ListTile(
                leading: Icon(Icons.center_focus_strong_rounded),
                title: const Text('适应画布'),
                onTap: () => Navigator.pop(context, 'fit'),
              ),
              ListTile(
                leading: Icon(Icons.bug_report_outlined),
                title: const Text('调试'),
                subtitle: const Text('查看 Node-RED debug 输出'),
                onTap: () => Navigator.pop(context, 'debug'),
              ),
              ListTile(
                leading: Icon(Icons.content_copy_rounded),
                title: const Text('复制 Flow JSON'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              if (!_isDemo)
                ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: const Text('从实例重新载入'),
                  onTap: () => Navigator.pop(context, 'reload'),
                ),
              ListTile(
                leading: Icon(Icons.hub_outlined),
                title: Text(_isDemo ? '示例画布' : widget.connection.name),
                subtitle: Text(_isDemo ? '未连接实例' : widget.connection.baseUrl),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _openPicker(
          worldPoint: _canvasKey.currentState?.worldCenter ?? Offset.zero,
        );
        break;
      case 'fit':
        _canvasKey.currentState?.resetView();
        break;
      case 'debug':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => DebugScreen(
              connection: widget.connection,
              service: _debugService,
            ),
          ),
        );
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: jsonEncode(_nodes)));
        _showMessage('Flow JSON 已复制');
        break;
      case 'reload':
        await _reloadFromInstance();
        break;
    }
  }

  Future<void> _reloadFromInstance() async {
    if (_isDemo) return;
    if (_isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新载入 Flow？'),
          content: const Text('本地未部署的修改会被丢弃。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新载入'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    setState(() => _deploying = true);
    try {
      final latest = await _api.getFlows(widget.connection);
      _installRemote(latest);
      _haCatalogLoaded = false;
      _haCatalog = const HomeAssistantCatalog();
      await _loadHomeAssistantCatalog();
      _showMessage('已从实例载入最新 Flow');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  void _installRemote(FlowBundle remote) {
    var nodes = cloneNodes(remote.nodes);
    var tabs = nodes.where((node) => node['type'] == 'tab').toList();
    if (tabs.isEmpty) {
      final id = createNodeId();
      nodes.insert(0, {
        'id': id,
        'type': 'tab',
        'label': 'Flow 1',
        'disabled': false,
        'info': '',
        'env': [],
      });
      tabs = nodes.where((node) => node['type'] == 'tab').toList();
    }
    setState(() {
      _nodes = nodes;
      _deployedNodes = cloneNodes(nodes);
      _bundle = remote;
      _activeTabId = tabs.first['id'].toString();
      _selectedNodeId = null;
      _selectedLink = null;
      _undoStack = [];
      _redoStack = [];
      _isConflict = false;
      _conflictRemote = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _canvasKey.currentState?.resetView(),
    );
  }

  Future<void> _deploy() async {
    if (_isDemo || !_isDirty || _deploying || _isConflict) return;
    setState(() => _deploying = true);
    try {
      final result = await _api.deploy(
        widget.connection,
        _bundle.copyWith(nodes: cloneNodes(_nodes)),
        baseline: _deployedNodes,
      );
      if (!mounted) return;
      setState(() {
        _bundle = result.copyWith(nodes: cloneNodes(_nodes));
        _deployedNodes = cloneNodes(_nodes);
        _undoStack = [];
        _redoStack = [];
      });
      _showMessage('已部署到 ${widget.connection.name}');
    } on FlowConflictException {
      FlowBundle? remote;
      try {
        remote = await _api.getFlows(widget.connection);
      } catch (_) {
        remote = null;
      }
      if (!mounted) return;
      setState(() {
        _isConflict = true;
        _conflictRemote = remote;
      });
      await _showConflict();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  Future<void> _showConflict() async {
    final remote = _conflictRemote;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.sync_problem_rounded, color: RivlenColors.amber),
        title: const Text('实例中的 Flow 已更新'),
        content: Text(
          remote == null
              ? 'Node-RED 拒绝了过期 revision 的部署。Rivlen 没有覆盖实例。请检查连接后再载入最新 Flow。'
              : '其他编辑端已部署较新的 revision。Rivlen 已阻止本次部署，避免覆盖实例上的修改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('保留草稿'),
          ),
          if (remote != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'reload'),
              child: const Text('复制草稿并载入实例'),
            ),
        ],
      ),
    );
    if (action == 'reload' && remote != null) {
      await Clipboard.setData(ClipboardData(text: jsonEncode(_nodes)));
      _installRemote(remote);
      _showMessage('本地草稿已复制到剪贴板，并载入了实例版本');
    }
  }

  Future<void> _leaveEditor() async {
    if (!_isDirty) {
      if (mounted) {
        setState(() => _allowPop = true);
        Navigator.pop(context);
      }
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保留未部署的修改？'),
        content: const Text('返回实例列表后，未部署的修改会被丢弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('丢弃并返回'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tabLabel =
        (_activeTab['label']?.toString().trim().isNotEmpty ?? false)
        ? _activeTab['label'].toString()
        : 'Flow';
    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_deploying && !_allowPop) _leaveEditor();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          leadingWidth: 48,
          leading: IconButton(
            onPressed: _deploying ? null : _leaveEditor,
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            tooltip: '返回实例',
          ),
          titleSpacing: 4,
          title: InkWell(
            onTap: _showFlows,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          tabLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, size: 19),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isConflict
                              ? RivlenColors.amber
                              : _isDirty
                              ? RivlenColors.coral
                              : RivlenColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isConflict
                            ? '版本冲突'
                            : _isDirty
                            ? '未部署修改'
                            : _isDemo
                            ? '示例画布'
                            : widget.connection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: RivlenColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            const RivlenThemeButton(),
            IconButton(
              tooltip: '撤销',
              onPressed: _canUndo ? _undo : null,
              icon: Icon(Icons.undo_rounded, size: 21),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: _canRedo ? _redo : null,
              icon: Icon(Icons.redo_rounded, size: 21),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 13, left: 1),
              child: SizedBox(
                height: 37,
                child: FilledButton(
                  onPressed: !_isDemo && _isDirty && !_deploying && !_isConflict
                      ? _deploy
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    minimumSize: Size.zero,
                    backgroundColor: RivlenColors.wine,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE9E4E0),
                    disabledForegroundColor: RivlenColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _deploying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('部署', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              height: 1,
              color: RivlenColors.line.withValues(alpha: 0.8),
            ),
            Expanded(
              child: FlowCanvas(
                key: _canvasKey,
                nodes: _visibleNodes,
                selectedNodeId: _selectedNodeId,
                selectedLink: _selectedLink,
                onSelectNode: (id) => setState(() {
                  _selectedNodeId = id;
                  _selectedLink = null;
                }),
                onClearSelection: () => setState(() {
                  _selectedNodeId = null;
                  _selectedLink = null;
                }),
                onEditNode: _editNode,
                onMoveNode: _moveNode,
                onMoveEnd: _endMove,
                onConnect: _connect,
                onAddAtWireEnd: (source, output, point) => _openPicker(
                  worldPoint: point,
                  sourceId: source,
                  outputIndex: output,
                ),
                onAddAtPoint: (point) => _openPicker(worldPoint: point),
                onSelectLink: _selectLink,
                onFitBounds: () => _canvasKey.currentState?.resetView(),
              ),
            ),
            if (_selectedNode != null)
              _SelectedNodeBar(
                node: _selectedNode!,
                onEdit: () => _editNode(_selectedNodeId!),
                onDelete: () => _deleteNode(_selectedNodeId!),
                onInject: () => _injectNode(_selectedNodeId!),
                isInjecting: _injectingNodeId == _selectedNodeId,
              ),
            _BottomBar(
              tabLabel: tabLabel,
              onFlows: _showFlows,
              onSearch: _search,
              onMore: _more,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedNodeBar extends StatelessWidget {
  const _SelectedNodeBar({
    required this.node,
    required this.onEdit,
    required this.onDelete,
    required this.onInject,
    required this.isInjecting,
  });

  final FlowNode node;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onInject;
  final bool isInjecting;

  @override
  Widget build(BuildContext context) {
    final type = node['type']?.toString() ?? '';
    return Material(
      color: RivlenColors.surface,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: RivlenColors.line)),
          ),
          child: Row(
            children: [
              _NodeGlyph(type: type),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nodeTitle(node),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '类型 · $type',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: RivlenColors.muted),
                    ),
                  ],
                ),
              ),
              if (type == 'inject')
                TextButton.icon(
                  onPressed: isInjecting ? null : onInject,
                  icon: isInjecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('触发'),
                  style: TextButton.styleFrom(
                    foregroundColor: RivlenColors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              TextButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, size: 17),
                label: const Text('删除'),
                style: TextButton.styleFrom(
                  foregroundColor: RivlenColors.wine,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabLabel,
    required this.onFlows,
    required this.onSearch,
    required this.onMore,
  });
  final String tabLabel;
  final VoidCallback onFlows;
  final VoidCallback onSearch;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: RivlenColors.surface,
      border: Border(top: BorderSide(color: RivlenColors.line)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            Expanded(
              child: _BottomAction(
                icon: Icons.account_tree_outlined,
                label: tabLabel,
                onTap: onFlows,
              ),
            ),
            Expanded(
              child: _BottomAction(
                icon: Icons.search_rounded,
                label: '搜索',
                onTap: onSearch,
              ),
            ),
            Expanded(
              child: _BottomAction(
                icon: Icons.more_horiz_rounded,
                label: '更多',
                onTap: onMore,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 19, color: RivlenColors.ink),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: RivlenColors.muted),
        ),
      ],
    ),
  );
}

class _NodeGlyph extends StatelessWidget {
  const _NodeGlyph({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = nodeColor(type).color;
    return Container(
      width: 37,
      height: 37,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        nodeColor(type).glyph,
        style: TextStyle(
          color: color,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({
    required this.recentTypes,
    required this.additionalNodeKinds,
    required this.acceptsInput,
    required this.acceptsOutput,
  });
  final List<String> recentTypes;
  final List<NodeKind> additionalNodeKinds;
  final bool acceptsInput;
  final bool acceptsOutput;

  @override
  State<_NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<_NodePickerSheet> {
  final _search = TextEditingController();
  String _category = '全部';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const categories = [
      '全部',
      '最近',
      'Input',
      'Function',
      'Network',
      'Output',
      'Other',
      'Home Assistant',
      '已安装节点',
    ];
    final allKinds = <NodeKind>[...nodeKinds, ...widget.additionalNodeKinds];
    final available = allKinds.where((kind) {
      if (kind.type == 'junction') return false;
      if (widget.acceptsInput && !nodeHasInput({'type': kind.type})) {
        return false;
      }
      if (widget.acceptsOutput && !nodeHasOutput({'type': kind.type})) {
        return false;
      }
      return true;
    }).toList();
    final query = _search.text.trim().toLowerCase();
    final nodes = available.where((kind) {
      final categoryMatch = switch (_category) {
        '全部' => true,
        '最近' => widget.recentTypes.contains(kind.type),
        _ => kind.category == _category,
      };
      final textMatch =
          query.isEmpty ||
          '${kind.title} ${kind.type} ${kind.description}'
              .toLowerCase()
              .contains(query);
      return categoryMatch && textMatch;
    }).toList();
    if (_category == '最近') {
      nodes.sort(
        (a, b) => widget.recentTypes
            .indexOf(a.type)
            .compareTo(widget.recentTypes.indexOf(b.type)),
      );
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          13,
          18,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: rivlenSheetHeight(context, 0.79),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: RivlenColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择节点',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${nodes.length}',
                    style: TextStyle(color: RivlenColors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索节点类型',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 37,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = _category == category;
                    return ChoiceChip(
                      label: Text(category),
                      selected: selected,
                      onSelected: (_) => setState(() => _category = category),
                      showCheckmark: false,
                      backgroundColor: RivlenColors.canvas,
                      selectedColor: RivlenColors.wine.withValues(alpha: 0.1),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? RivlenColors.wine
                            : RivlenColors.muted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      side: BorderSide(
                        color: selected
                            ? RivlenColors.wine.withValues(alpha: 0.28)
                            : RivlenColors.line,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: nodes.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的节点',
                          style: TextStyle(color: RivlenColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, indent: 51),
                        itemBuilder: (context, index) {
                          final kind = nodes[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                            ),
                            leading: _NodeGlyph(type: kind.type),
                            title: Text(
                              kind.title,
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(kind.description, maxLines: 1),
                            trailing: Icon(
                              Icons.add_rounded,
                              color: RivlenColors.muted,
                            ),
                            onTap: () => Navigator.pop(context, kind),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeEditorSheet extends StatefulWidget {
  const _NodeEditorSheet({
    required this.initial,
    this.schema = const NodeEditorSchema(),
  });
  final FlowNode initial;
  final NodeEditorSchema schema;

  @override
  State<_NodeEditorSheet> createState() => _NodeEditorSheetState();
}

class _NodeEditorSheetState extends State<_NodeEditorSheet> {
  late FlowNode _draft;
  late TextEditingController _name;
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(widget.initial);
    _name = TextEditingController(text: _draft['name']?.toString() ?? '');
    _syncControllers();
  }

  void _syncControllers() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    for (final field in _orderedFields(nodeEditorFields(_draft))) {
      _fields[field] = TextEditingController(
        text: _draft[field]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _typeLabel =>
      nodeKinds
          .where((kind) => kind.type == _draft['type'])
          .map((kind) => kind.title)
          .firstOrNull ??
      nodeTypeLabel(_draft['type']?.toString() ?? 'Node');

  List<String> _orderedFields(Iterable<String> fields) {
    final available = fields.toSet();
    final ordered = <String>[];
    for (final field in widget.schema.fieldOrder) {
      if (available.remove(field)) ordered.add(field);
    }
    for (final field in fields) {
      if (available.remove(field)) ordered.add(field);
    }
    return ordered;
  }

  Future<void> _editComplexField(String field) async {
    _applyControllers();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TextDocumentEditor(
          title: switch (field) {
            'func' => 'Function 代码',
            'template' => 'Template 内容',
            'info' => '节点说明',
            _ => field,
          },
          text: _draft[field]?.toString() ?? '',
          language: field == 'func' ? 'JavaScript' : 'Text',
        ),
      ),
    );
    if (result != null) setState(() => _draft[field] = result);
  }

  Future<void> _editRawJson() async {
    _applyControllers();
    final result = await Navigator.of(context).push<FlowNode>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RawNodeEditor(initial: _draft),
      ),
    );
    if (result != null) {
      setState(() {
        _draft = result;
        _name.text = _draft['name']?.toString() ?? '';
        _syncControllers();
      });
    }
  }

  Future<void> _editStructuredField(String field) async {
    _applyControllers();
    final result = await Navigator.of(context).push<_NodeValueEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _NodeValueEditor(
          title: _humanize(field),
          initialValue: _draft[field],
        ),
      ),
    );
    if (result != null) setState(() => _draft[field] = result.value);
  }

  void _applyControllers() {
    for (final entry in _fields.entries) {
      final original = _draft[entry.key];
      final text = entry.value.text.trim();
      if (original is int) {
        _draft[entry.key] = int.tryParse(text) ?? original;
      } else if (original is double) {
        _draft[entry.key] = double.tryParse(text) ?? original;
      } else if (original is num) {
        _draft[entry.key] = num.tryParse(text) ?? original;
      } else {
        _draft[entry.key] = text;
      }
    }
  }

  void _save() {
    _draft['name'] = _name.text.trim();
    _applyControllers();
    Navigator.pop(context, _draft);
  }

  @override
  Widget build(BuildContext context) {
    final complex = complexField(_draft);
    final structured = nodeStructuredFields(_draft);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + viewInsets),
        child: SizedBox(
          height: rivlenSheetHeight(context, 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RivlenColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  _NodeGlyph(type: _draft['type'].toString()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '编辑节点',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: RivlenColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除节点',
                    onPressed: () => Navigator.pop(context, <String, dynamic>{
                      '__delete': true,
                    }),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: RivlenColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: '名称',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._orderedFields(nodeEditorFields(_draft)).map((field) {
                      final value = _draft[field];
                      if (value is bool) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _GenericFormSwitchField(
                            title: _humanize(field),
                            value: value,
                            onChanged: (next) =>
                                setState(() => _draft[field] = next),
                          ),
                        );
                      }
                      final controller = _fields[field];
                      if (controller == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: controller,
                          keyboardType: _keyboardType(value),
                          decoration: InputDecoration(
                            labelText: _humanize(field),
                            prefixIcon: Icon(_fieldIcon(field)),
                          ),
                        ),
                      );
                    }),
                    if (complex != null) ...[
                      const SizedBox(height: 2),
                      _EditorActionTile(
                        icon: Icons.code_rounded,
                        title: switch (complex) {
                          'func' => '编辑 JavaScript',
                          'template' => '编辑模板',
                          _ => '编辑说明',
                        },
                        subtitle: _preview(_draft[complex]?.toString() ?? ''),
                        onTap: () => _editComplexField(complex),
                      ),
                    ],
                    ...structured.map(
                      (field) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _EditorActionTile(
                          icon: Icons.data_object_rounded,
                          title: '编辑 ${_humanize(field)}',
                          subtitle: _structuredSummary(_draft[field]),
                          onTap: () => _editStructuredField(field),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _EditorActionTile(
                      icon: Icons.data_object_rounded,
                      title: '高级配置',
                      subtitle: '查看并编辑完整节点 JSON',
                      onTap: _editRawJson,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: RivlenColors.wine,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('保存修改'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextInputType _keyboardType(dynamic value) {
    if (value is int || value is double || value is num) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.text;
  }

  String _humanize(String value) {
    final provided = widget.schema.labelFor(value);
    if (provided != null && provided.isNotEmpty) return provided;
    return switch (value) {
      'name' => '名称',
      'topic' => '主题',
      'payload' => '消息内容',
      'repeat' => '重复间隔（秒）',
      'outputs' => '输出数量',
      'property' => '消息属性',
      'timeout' => '延迟时长',
      'timeoutUnits' => '时间单位',
      'field' => '写入字段',
      'method' => '请求方法',
      'url' => '请求地址',
      'qos' => 'QoS',
      'entityId' || 'entity_id' => '实体',
      'entityidfilter' || 'entity_id_filter' => '实体筛选',
      'server' => '服务器',
      'domain' => '域',
      'service' => '服务',
      'service_domain' => '服务域',
      'action' => '动作',
      'dataType' => '数据类型',
      'halt_if' => '停止条件',
      'halt_if_type' => '条件类型',
      'halt_if_compare' => '比较方式',
      'outputInitially' => '初始输出',
      'stateType' => '状态类型',
      'for' => '持续时间',
      'forType' => '持续时间类型',
      'forUnits' => '时间单位',
      _ =>
        value
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match.group(1)} ${match.group(2)}',
            )
            .replaceAll(RegExp(r'[_-]+'), ' '),
    };
  }

  String _structuredSummary(dynamic value) {
    if (value == null) return '未设置 · 点击编辑';
    if (value is Map) return '${value.length} 项配置 · 点击编辑';
    if (value is List) return '${value.length} 项 · 点击编辑';
    return '已配置 · 点击编辑';
  }

  IconData _fieldIcon(String key) => switch (key) {
    'url' => Icons.link_rounded,
    'repeat' || 'timeout' || 'timeoutUnits' => Icons.schedule_rounded,
    'topic' => Icons.tag_rounded,
    'payload' => Icons.data_object_rounded,
    'entityId' || 'entity_id' => Icons.devices_other_rounded,
    'server' => Icons.dns_outlined,
    'domain' || 'service' || 'action' => Icons.home_work_outlined,
    _ => Icons.tune_rounded,
  };
}

class _NodeValueEditResult {
  const _NodeValueEditResult(this.value);
  final dynamic value;
}

class _NodeValueEditor extends StatefulWidget {
  const _NodeValueEditor({required this.title, required this.initialValue});

  final String title;
  final dynamic initialValue;

  @override
  State<_NodeValueEditor> createState() => _NodeValueEditorState();
}

class _NodeValueEditorState extends State<_NodeValueEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(widget.initialValue),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    try {
      Navigator.pop(
        context,
        _NodeValueEditResult(jsonDecode(_controller.text)),
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('JSON 无效：${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded),
      ),
      title: Text(widget.title),
      actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(32),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '编辑此属性的 JSON 值',
              style: TextStyle(fontSize: 11, color: RivlenColors.muted),
            ),
          ),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _controller,
          expands: true,
          minLines: null,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
            color: RivlenColors.ink,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: RivlenColors.surface,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
          ),
        ),
      ),
    ),
  );
}

class _EditorActionTile extends StatelessWidget {
  const _EditorActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RivlenColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: RivlenColors.wine),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: RivlenColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: RivlenColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: RivlenColors.muted,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenericFormSwitchField extends StatelessWidget {
  const _GenericFormSwitchField({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: RivlenColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: SwitchListTile.adaptive(
      value: value,
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      onChanged: onChanged,
    ),
  );
}

class _TextDocumentEditor extends StatefulWidget {
  const _TextDocumentEditor({
    required this.title,
    required this.text,
    required this.language,
  });
  final String title;
  final String text;
  final String language;

  @override
  State<_TextDocumentEditor> createState() => _TextDocumentEditorState();
}

class _TextDocumentEditorState extends State<_TextDocumentEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded),
      ),
      title: Text(widget.title),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('完成'),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 14, color: RivlenColors.muted),
              const SizedBox(width: 6),
              Text(
                widget.language,
                style: TextStyle(color: RivlenColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _controller,
          expands: true,
          minLines: null,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
            color: RivlenColors.ink,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: RivlenColors.surface,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RawNodeEditor extends StatefulWidget {
  const _RawNodeEditor({required this.initial});
  final FlowNode initial;

  @override
  State<_RawNodeEditor> createState() => _RawNodeEditorState();
}

class _RawNodeEditorState extends State<_RawNodeEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(widget.initial),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) throw const FormatException('JSON 根节点必须是对象。');
      final node = Map<String, dynamic>.from(decoded);
      for (final field in ['id', 'type', 'z']) {
        if (node[field]?.toString() != widget.initial[field]?.toString()) {
          throw FormatException('$field 字段由 Rivlen 管理，不能在高级编辑器中修改。');
        }
      }
      Navigator.pop(context, node);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('JSON 无效：${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded),
      ),
      title: const Text('节点 JSON'),
      actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(32),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '未修改的未知字段会完整保留',
              style: TextStyle(fontSize: 11, color: RivlenColors.muted),
            ),
          ),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _controller,
          expands: true,
          minLines: null,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.45,
            color: RivlenColors.ink,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: RivlenColors.surface,
            contentPadding: const EdgeInsets.all(15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: RivlenColors.line),
            ),
          ),
        ),
      ),
    ),
  );
}

String _preview(String value) {
  final compact = value.trim().replaceAll('\n', ' ');
  if (compact.isEmpty) return '未设置';
  return compact.length > 68 ? '${compact.substring(0, 68)}…' : compact;
}
