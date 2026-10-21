import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/node_catalog.dart';
import '../models/flow_bundle.dart';
import '../models/node_red_connection.dart';
import '../services/node_red_api.dart';
import '../theme.dart';
import '../widgets/flow_canvas.dart';

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
  List<List<FlowNode>> _undoStack = [];
  List<List<FlowNode>> _redoStack = [];
  List<String> _recentTypes = [];

  bool get _isDemo => widget.connection.id == 'demo';
  bool get _isDirty => _canonical(_nodes) != _canonical(_deployedNodes);
  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _api = NodeRedApi();
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
  }

  @override
  void dispose() {
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

  List<FlowNode> get _visibleNodes => _nodes
      .where(
        (node) =>
            node['type'] != 'tab' && node['z']?.toString() == _activeTabId,
      )
      .toList(growable: false);

  String _canonical(List<FlowNode> nodes) => jsonEncode(nodes);

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
      for (final peer in _visibleNodes.where(
        (item) => item['id'].toString() != id,
      )) {
        final peerX = (peer['x'] as num?)?.toDouble();
        final peerY = (peer['y'] as num?)?.toDouble();
        if (peerX != null && (x - peerX).abs() < 12) x = peerX;
        if (peerY != null && (y - peerY).abs() < 12) y = peerY;
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
    final result = await showModalBottomSheet<FlowNode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NodeEditorSheet(initial: original),
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
    setState(() => _selectedLink = link);
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
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('在线上插入节点'),
                onTap: () => Navigator.pop(context, 'insert'),
              ),
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
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
              const Text(
                '切换 Flow',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ...tabs.map((tab) {
                final id = tab['id'].toString();
                final count = _nodes
                    .where((node) => node['z']?.toString() == id)
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
                  title: Text(
                    (tab['label']?.toString().trim().isNotEmpty ?? false)
                        ? tab['label'].toString()
                        : 'Flow',
                  ),
                  subtitle: Text('$count 个节点'),
                  trailing: IconButton(
                    tooltip: '重命名 Flow',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      Navigator.pop(context, 'rename:$id');
                    },
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
    if (selected.startsWith('rename:')) {
      await _renameFlow(selected.substring(7));
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
          decoration: const InputDecoration(labelText: '名称'),
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
                height: MediaQuery.sizeOf(context).height * 0.72,
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
                      decoration: const InputDecoration(
                        hintText: '搜索节点',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: results.isEmpty
                          ? const Center(
                              child: Text(
                                '没有匹配的节点',
                                style: TextStyle(color: RivlenColors.muted),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, indent: 54),
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
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('添加节点'),
                onTap: () => Navigator.pop(context, 'add'),
              ),
              ListTile(
                leading: const Icon(Icons.center_focus_strong_rounded),
                title: const Text('适应画布'),
                onTap: () => Navigator.pop(context, 'fit'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_rounded),
                title: const Text('复制 Flow JSON'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              if (!_isDemo)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('从实例重新载入'),
                  onTap: () => Navigator.pop(context, 'reload'),
                ),
              ListTile(
                leading: const Icon(Icons.hub_outlined),
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
        icon: const Icon(Icons.sync_problem_rounded, color: RivlenColors.amber),
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
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
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded, size: 19),
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
                        style: const TextStyle(
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
            IconButton(
              tooltip: '撤销',
              onPressed: _canUndo ? _undo : null,
              icon: const Icon(Icons.undo_rounded, size: 21),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: _canRedo ? _redo : null,
              icon: const Icon(Icons.redo_rounded, size: 21),
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
    decoration: const BoxDecoration(
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
          style: const TextStyle(fontSize: 10, color: RivlenColors.muted),
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
        ),
      ),
    );
  }
}

class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({
    required this.recentTypes,
    required this.acceptsInput,
    required this.acceptsOutput,
  });
  final List<String> recentTypes;
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
    ];
    final available = nodeKinds.where((kind) {
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
          height: MediaQuery.sizeOf(context).height * 0.79,
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
                    style: const TextStyle(
                      color: RivlenColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
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
                    ? const Center(
                        child: Text(
                          '没有匹配的节点',
                          style: TextStyle(color: RivlenColors.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 51),
                        itemBuilder: (context, index) {
                          final kind = nodes[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                            ),
                            leading: _NodeGlyph(type: kind.type),
                            title: Text(
                              kind.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(kind.description, maxLines: 1),
                            trailing: const Icon(
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
  const _NodeEditorSheet({required this.initial});
  final FlowNode initial;

  @override
  State<_NodeEditorSheet> createState() => _NodeEditorSheetState();
}

class _NodeEditorSheetState extends State<_NodeEditorSheet> {
  late FlowNode _draft;
  late TextEditingController _name;
  late Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(widget.initial);
    _name = TextEditingController(text: _draft['name']?.toString() ?? '');
    _fields = {
      for (final field in editableFields(_draft))
        field: TextEditingController(text: _draft[field]?.toString() ?? ''),
    };
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
      _draft['type']?.toString() ??
      'Node';

  Future<void> _editComplexField(String field) async {
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
        for (final entry in _fields.entries) {
          entry.value.text = _draft[entry.key]?.toString() ?? '';
        }
      });
    }
  }

  void _save() {
    _draft['name'] = _name.text.trim();
    for (final entry in _fields.entries) {
      final original = widget.initial[entry.key];
      final text = entry.value.text;
      if (original is int) {
        _draft[entry.key] = int.tryParse(text) ?? original;
      } else if (original is double) {
        _draft[entry.key] = double.tryParse(text) ?? original;
      } else {
        _draft[entry.key] = text;
      }
    }
    Navigator.pop(context, _draft);
  }

  @override
  Widget build(BuildContext context) {
    final complex = complexField(_draft);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + viewInsets),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
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
                          style: const TextStyle(
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
                    icon: const Icon(
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
                      decoration: const InputDecoration(
                        labelText: '名称',
                        prefixIcon: Icon(Icons.label_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._fields.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: entry.value,
                          keyboardType:
                              entry.key == 'url' || entry.key == 'topic'
                              ? TextInputType.text
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: _humanize(entry.key),
                            prefixIcon: Icon(_fieldIcon(entry.key)),
                          ),
                        ),
                      ),
                    ),
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

  String _humanize(String value) => switch (value) {
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
    _ => value,
  };

  IconData _fieldIcon(String key) => switch (key) {
    'url' => Icons.link_rounded,
    'repeat' || 'timeout' || 'timeoutUnits' => Icons.schedule_rounded,
    'topic' => Icons.tag_rounded,
    'payload' => Icons.data_object_rounded,
    _ => Icons.tune_rounded,
  };
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
  Widget build(BuildContext context) => Material(
    color: RivlenColors.canvas,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(13),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: RivlenColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
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
        icon: const Icon(Icons.close_rounded),
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
              const Icon(
                Icons.code_rounded,
                size: 14,
                color: RivlenColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                widget.language,
                style: const TextStyle(color: RivlenColors.muted, fontSize: 11),
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
          style: const TextStyle(
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
              borderSide: const BorderSide(color: RivlenColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: RivlenColors.line),
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
        icon: const Icon(Icons.close_rounded),
      ),
      title: const Text('节点 JSON'),
      actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      bottom: const PreferredSize(
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
          style: const TextStyle(
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
              borderSide: const BorderSide(color: RivlenColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: RivlenColors.line),
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
