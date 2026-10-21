import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/node_catalog.dart';
import '../models/flow_bundle.dart';
import '../models/home_assistant_catalog.dart';
import '../theme.dart';

/// A native editor for the Home Assistant Node-RED nodes.
///
/// The editor is deliberately schema tolerant.  Known HA controls use native
/// pickers backed by the connected Node-RED instance, while new fields added
/// by the HA package remain editable as ordinary controls and are preserved
/// when the node is saved.
class HomeAssistantNodeEditor extends StatefulWidget {
  const HomeAssistantNodeEditor({
    super.key,
    required this.initial,
    required this.catalog,
    this.fieldLabels = const {},
  });

  final FlowNode initial;
  final HomeAssistantCatalog catalog;
  final Map<String, String> fieldLabels;

  @override
  State<HomeAssistantNodeEditor> createState() =>
      _HomeAssistantNodeEditorState();
}

class _HomeAssistantNodeEditorState extends State<HomeAssistantNodeEditor> {
  late FlowNode _draft;
  late final TextEditingController _name;
  final Map<String, TextEditingController> _fields = {};

  String get _type => _draft['type']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(widget.initial);
    _applyNativeDefaults();
    _name = TextEditingController(text: _draft['name']?.toString() ?? '');
    _syncControllers();
  }

  void _applyNativeDefaults() {
    void put(String key, dynamic value) {
      if (!_draft.containsKey(key)) _draft[key] = value;
    }

    put('server', '');
    switch (_type) {
      case 'api-call-service':
        put('action', '');
        put('floorId', <String>[]);
        put('areaId', <String>[]);
        put('deviceId', <String>[]);
        put('entityId', <String>[]);
        put('labelId', <String>[]);
        put('data', '');
        put('dataType', 'jsonata');
        put('queue', 'none');
        put('debugenabled', false);
        put('blockInputOverrides', true);
        break;
      case 'api-current-state':
        put('entity_id', '');
        put('halt_if', '');
        put('halt_if_type', 'str');
        put('halt_if_compare', 'is');
        put('state_type', 'str');
        put('for', '0');
        put('forType', 'num');
        put('forUnits', 'minutes');
        break;
      case 'server-state-changed':
      case 'trigger-state':
        put('entities', <String, dynamic>{
          'entity': <String>[],
          'substring': <String>[],
          'regex': <String>[],
        });
        put('ifState', '');
        put('ifStateType', 'str');
        put('ifStateOperator', 'is');
        put('for', '0');
        put('forType', 'num');
        put('forUnits', 'minutes');
        put('stateType', 'str');
        break;
      case 'ha-api':
        put('protocol', 'http');
        put('method', 'get');
        put('path', '');
        put('data', '');
        put('responseType', 'json');
        break;
      case 'ha-device':
        put('deviceType', 'action');
        put('device', '');
        break;
      case 'ha-get-entities':
        put('outputType', 'array');
        break;
      case 'api-get-history':
        put('entityId', <String>[]);
        put('entityIdType', 'equals');
        put('outputType', 'array');
        break;
      case 'poll-state':
        put('entityId', <String>[]);
        put('updateInterval', '60');
        put('updateIntervalUnits', 'seconds');
        put('ifStateOperator', 'is');
        break;
      case 'ha-zone':
        put('zone', '');
        put('event', 'enter');
        break;
      case 'ha-time':
      case 'ha-time-entity':
        put('entityId', '');
        put('offset', '0');
        put('offsetUnits', 'seconds');
        break;
      default:
        // The server selector above is the useful common field for the rest
        // of the Home Assistant node family.
        break;
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

  void _syncControllers() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    for (final field in nodeEditorFields(_draft)) {
      if (_isPickerField(field) || _isHiddenByNativeField(field)) continue;
      _fields[field] = TextEditingController(
        text: _draft[field]?.toString() ?? '',
      );
    }
  }

  bool _isHiddenByNativeField(String field) {
    if (field == 'version') return true;
    if (field == 'domain' || field == 'service') {
      return _type == 'api-call-service';
    }
    return false;
  }

  bool _isPickerField(String field) {
    if (field == 'server') return true;
    if (_type == 'api-call-service' && field == 'action') return true;
    return _isEntityField(field);
  }

  bool _isEntityField(String field) {
    final key = field.toLowerCase();
    return key == 'entityid' ||
        key == 'entity_id' ||
        key == 'entity' ||
        key == 'entityidfilter' ||
        key == 'entity_id_filter' ||
        key == 'device' ||
        key == 'deviceid' ||
        key == 'device_id' ||
        key == 'area' ||
        key == 'areaid' ||
        key == 'area_id' ||
        key == 'floor' ||
        key == 'floorid' ||
        key == 'floor_id' ||
        key == 'labelid' ||
        key == 'label_id';
  }

  bool _isEntityMapField(String field) =>
      field == 'entities' && _draft[field] is Map;

  String _label(String field) {
    final native = switch (field) {
      'server' => 'Home Assistant 服务器',
      'action' => '动作',
      'domain' => '域',
      'service' => '服务',
      'entityId' || 'entity_id' || 'entity' => '实体',
      'entities' => '实体',
      'deviceId' || 'device_id' || 'device' => '设备',
      'areaId' || 'area_id' || 'area' => '区域',
      'floorId' || 'floor_id' || 'floor' => '楼层',
      'labelId' || 'label_id' || 'label' => '标签',
      'data' => '服务数据',
      'dataType' => '数据类型',
      'halt_if' => '状态条件',
      'halt_if_type' => '条件值类型',
      'halt_if_compare' => '比较方式',
      'ifState' => '状态条件',
      'ifStateType' => '条件值类型',
      'ifStateOperator' => '比较方式',
      'stateType' => '状态类型',
      'for' => '持续时间',
      'forType' => '持续时间类型',
      'forUnits' => '时间单位',
      'outputInitially' => '初始输出',
      'outputOnlyOnStateChange' => '仅状态变化时输出',
      'debugenabled' || 'debugEnabled' => '调试输出',
      'blockInputOverrides' => '阻止输入覆盖',
      'queue' => '队列模式',
      'deviceType' => '设备节点类型',
      'outputType' => '输出类型',
      _ => null,
    };
    if (native != null) return native;
    final value = widget.fieldLabels[field]?.trim();
    if (value != null && value.isNotEmpty) return value;
    return _humanize(field);
  }

  String _humanize(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();

  String get _typeLabel => nodeTypeLabel(_type);

  void _set(String field, dynamic value) {
    setState(() => _draft[field] = value);
  }

  void _applyControllers() {
    for (final entry in _fields.entries) {
      final original = _draft[entry.key];
      final value = entry.value.text;
      if (original is int) {
        _draft[entry.key] = int.tryParse(value.trim()) ?? original;
      } else if (original is double) {
        _draft[entry.key] = double.tryParse(value.trim()) ?? original;
      } else if (original is num) {
        _draft[entry.key] = num.tryParse(value.trim()) ?? original;
      } else {
        _draft[entry.key] = value;
      }
    }
  }

  void _save() {
    _applyControllers();
    _draft['name'] = _name.text.trim();
    Navigator.pop(context, _draft);
  }

  Future<void> _editJsonField(String field) async {
    _applyControllers();
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(_draft[field]),
    );
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(_label(field)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: controller,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      setState(() => _draft[field] = jsonDecode(result));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('配置 JSON 无效')));
    }
  }

  Future<String?> _pickService() async {
    final current = _draft['action']?.toString() ?? '';
    final services = widget.catalog.services;
    if (services.isEmpty) {
      return _pickFromText('动作', current);
    }
    final search = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = search.text.trim().toLowerCase();
          final filtered = services.where((service) {
            final haystack = '${service.key} ${service.description}'
                .toLowerCase();
            return query.isEmpty || haystack.contains(query);
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text('选择动作', style: Theme.of(context).textTheme.titleMedium),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: '搜索域或服务',
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final service = filtered[index];
                        return ListTile(
                          title: Text(service.key),
                          subtitle: service.description.isEmpty
                              ? null
                              : Text(service.description, maxLines: 2),
                          trailing: service.key == current
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, service.key),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    search.dispose();
    return selected;
  }

  Future<String?> _pickFromText(String title, String value) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<List<String>?> _pickValues({
    required String title,
    required List<HomeAssistantOption> options,
    required List<String> selected,
  }) async {
    if (options.isEmpty) {
      final result = await _pickFromText(title, selected.join(', '));
      if (result == null) return null;
      return entityIdsFromValue(result);
    }
    final query = TextEditingController();
    final picked = selected.toSet();
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RivlenColors.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalized = query.text.trim().toLowerCase();
          final filtered = options.where((option) {
            final haystack = '${option.id} ${option.label}'.toLowerCase();
            return normalized.isEmpty || haystack.contains(normalized);
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: query,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: '搜索名称或 ID',
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final option = filtered[index];
                        final checked = picked.contains(option.id);
                        return CheckboxListTile(
                          value: checked,
                          title: Text(
                            option.label.isEmpty ? option.id : option.label,
                          ),
                          subtitle: option.label.isEmpty
                              ? null
                              : Text(option.id),
                          onChanged: (value) => setSheetState(() {
                            if (value == true) {
                              picked.add(option.id);
                            } else {
                              picked.remove(option.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, picked.toList()),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: RivlenColors.wine,
                      ),
                      child: Text('完成（${picked.length}）'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    query.dispose();
    return result;
  }

  List<HomeAssistantOption> _optionsFor(String field) {
    final key = field.toLowerCase();
    if (key == 'device' || key == 'deviceid' || key == 'device_id') {
      return widget.catalog.devices;
    }
    if (key == 'area' || key == 'areaid' || key == 'area_id') {
      return widget.catalog.areas;
    }
    if (key == 'floor' || key == 'floorid' || key == 'floor_id') {
      return widget.catalog.floors;
    }
    if (key == 'label' || key == 'labelid' || key == 'label_id') {
      return widget.catalog.labels;
    }
    return widget.catalog.entities
        .map(
          (entity) => HomeAssistantOption(id: entity.id, label: entity.label),
        )
        .toList();
  }

  Future<void> _editSelectionField(String field) async {
    _applyControllers();
    final current = entityIdsFromValue(_draft[field]);
    final result = await _pickValues(
      title: _label(field),
      options: _optionsFor(field),
      selected: current,
    );
    if (result != null) {
      setState(
        () => _draft[field] = entityValueWithShape(_draft[field], result),
      );
    }
  }

  Future<void> _editEntityMap() async {
    final entities = _draft['entities'];
    if (entities is! Map) return;
    final selected = entityIdsFromValue(entities['entity']);
    final result = await _pickValues(
      title: '实体',
      options: _optionsFor('entityId'),
      selected: selected,
    );
    if (result == null) return;
    final next = Map<String, dynamic>.from(entities);
    next['entity'] = result;
    setState(() => _draft['entities'] = next);
  }

  Widget _serverField() {
    final values = <String>{
      ...widget.catalog.serverNames.keys,
      if ((_draft['server']?.toString() ?? '').isNotEmpty)
        _draft['server'].toString(),
    }.toList()..sort();
    if (values.isEmpty) {
      return _textField('server');
    }
    final current = _draft['server']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: values.contains(current) ? current : null,
        decoration: InputDecoration(
          labelText: _label('server'),
          prefixIcon: const Icon(Icons.dns_outlined),
        ),
        items: values
            .map(
              (value) => DropdownMenuItem<String>(
                value: value,
                child: Text(widget.catalog.serverNames[value] ?? value),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) _set('server', value);
        },
      ),
    );
  }

  Widget _serviceField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _HaSelectionTile(
      icon: Icons.bolt_rounded,
      title: _label('action'),
      subtitle: _draft['action']?.toString().trim().isNotEmpty == true
          ? _draft['action'].toString()
          : '选择 Home Assistant 服务',
      onTap: () async {
        final selected = await _pickService();
        if (selected == null || selected.isEmpty) return;
        final parts = selected.split('.');
        setState(() {
          _draft['action'] = selected;
          if (parts.length == 2) {
            _draft['domain'] = parts.first;
            _draft['service'] = parts.last;
          }
        });
      },
    ),
  );

  Widget _selectionField(String field) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _HaSelectionTile(
      icon: _iconForField(field),
      title: _label(field),
      subtitle: _selectionSummary(field),
      onTap: () => _editSelectionField(field),
    ),
  );

  String _selectionSummary(String field) {
    final selected = entityIdsFromValue(_draft[field]);
    if (selected.isEmpty) return '未选择';
    final labels = selected.map((id) {
      final entity = widget.catalog.entities.where((item) => item.id == id);
      if (entity.isNotEmpty && entity.first.label.isNotEmpty) {
        return entity.first.label;
      }
      final options = _optionsFor(field).where((item) => item.id == id);
      return options.isNotEmpty && options.first.label.isNotEmpty
          ? options.first.label
          : id;
    }).toList();
    return labels.join('、');
  }

  IconData _iconForField(String field) {
    final key = field.toLowerCase();
    if (key.contains('device')) return Icons.devices_other_rounded;
    if (key.contains('area')) return Icons.location_on_outlined;
    if (key.contains('floor')) return Icons.layers_outlined;
    if (key.contains('label')) return Icons.sell_outlined;
    return Icons.sensors_rounded;
  }

  Widget _entityMapField() {
    final entities = _draft['entities'];
    final selected = entities is Map
        ? entityIdsFromValue(entities['entity'])
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HaSelectionTile(
        icon: Icons.sensors_rounded,
        title: '实体',
        subtitle: selected.isEmpty ? '未选择' : selected.join('、'),
        onTap: _editEntityMap,
      ),
    );
  }

  Widget _textField(String field) {
    final controller = _fields[field];
    if (controller == null) return const SizedBox.shrink();
    final multiline = field == 'data' || field == 'eventData';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: multiline ? 4 : 1,
        keyboardType: multiline
            ? TextInputType.multiline
            : _keyboardType(_draft[field]),
        decoration: InputDecoration(
          labelText: _label(field),
          prefixIcon: Icon(_iconForField(field)),
          alignLabelWithHint: multiline,
        ),
      ),
    );
  }

  List<String> _staticOptions(String field) {
    final current = _draft[field]?.toString() ?? '';
    final options = switch (field) {
      'queue' => const ['none', 'first', 'all', 'last'],
      'halt_if_compare' || 'ifStateOperator' => const [
        'is',
        'is_not',
        'lt',
        'lte',
        'gt',
        'gte',
        'includes',
        'does_not_include',
        'jsonata',
      ],
      'halt_if_type' ||
      'ifStateType' ||
      'stateType' => const ['str', 'num', 'bool', 'jsonata'],
      'forType' => const ['num', 'msg', 'flow', 'global'],
      'forUnits' => const [
        'milliseconds',
        'seconds',
        'minutes',
        'hours',
        'days',
      ],
      'dataType' => const ['json', 'jsonata', 'str'],
      'protocol' => const ['websocket', 'http'],
      'method' => const ['get', 'post', 'put', 'delete'],
      'responseType' => const ['text', 'arraybuffer', 'json'],
      'inputOverride' => const ['allow', 'merge', 'block'],
      'deviceType' => const ['trigger', 'action'],
      'outputType' => const ['array', 'count', 'random', 'split'],
      'entityIdType' => const ['equals', 'regex'],
      'mode' => const ['listen', 'get', 'set'],
      'eventType' => const ['start', 'end'],
      'offsetUnits' || 'updateIntervalUnits' || 'timeoutUnits' => const [
        'milliseconds',
        'seconds',
        'minutes',
        'hours',
        'days',
      ],
      'triggerResponseType' => const ['fixed', 'dynamic'],
      'comparator' => const [
        'is',
        'is_not',
        'lt',
        'lte',
        'gt',
        'gte',
        'includes',
        'does_not_include',
        'jsonata',
      ],
      'event' => const ['enter', 'leave', 'enter_leave'],
      _ => const <String>[],
    };
    if (current.isNotEmpty && !options.contains(current)) {
      return [current, ...options];
    }
    return options;
  }

  Widget _optionField(String field) {
    final options = _staticOptions(field);
    if (options.isEmpty) return _textField(field);
    final current = _draft[field]?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(current) ? current : null,
        decoration: InputDecoration(labelText: _label(field)),
        items: options
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(_optionLabel(field, value)),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) _set(field, value);
        },
      ),
    );
  }

  String _optionLabel(String field, String value) {
    if (field == 'halt_if_compare' ||
        field == 'ifStateOperator' ||
        field == 'comparator') {
      return switch (value) {
        'is' => '等于',
        'is_not' => '不等于',
        'lt' => '小于',
        'lte' => '小于等于',
        'gt' => '大于',
        'gte' => '大于等于',
        'includes' => '包含',
        'does_not_include' => '不包含',
        'jsonata' => 'JSONata',
        _ => value,
      };
    }
    if (field == 'mode') {
      return switch (value) {
        'listen' => '监听',
        'get' => '读取',
        'set' => '设置',
        _ => value,
      };
    }
    if (field == 'queue') {
      return switch (value) {
        'none' => '不排队',
        'first' => '保留首个',
        'all' => '全部排队',
        'last' => '只保留最新',
        _ => value,
      };
    }
    return value;
  }

  HomeAssistantService? _selectedService() {
    final action = _draft['action']?.toString().trim() ?? '';
    if (action.isEmpty) return null;
    for (final service in widget.catalog.services) {
      if (service.key == action) return service;
    }
    return null;
  }

  Map<String, dynamic> _serviceData() {
    final value = _draft['data'];
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        // JSONata and mustache expressions remain in the text editor.
      }
    }
    return <String, dynamic>{};
  }

  void _setServiceDataValue(String field, dynamic value) {
    final data = _serviceData();
    if (value == null || (value is String && value.trim().isEmpty)) {
      data.remove(field);
    } else {
      data[field] = value;
    }
    final encoded = jsonEncode(data);
    setState(() {
      _draft['data'] = encoded == '{}' ? '' : encoded;
      _draft['dataType'] = 'json';
      _fields['data']?.text = _draft['data']?.toString() ?? '';
      _fields['dataType']?.text = 'json';
    });
  }

  Widget _serviceDataFields() {
    if (_type != 'api-call-service') return const SizedBox.shrink();
    final service = _selectedService();
    if (service == null || service.fields.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 8),
          child: Text(
            '动作参数',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        ...service.fields.entries.map(
          (entry) => _serviceDataField(entry.key, entry.value),
        ),
      ],
    );
  }

  Widget _serviceDataField(String field, dynamic definition) {
    final schema = definition is Map
        ? Map<String, dynamic>.from(definition)
        : const <String, dynamic>{};
    final selector = schema['selector'] is Map
        ? Map<String, dynamic>.from(schema['selector'] as Map)
        : const <String, dynamic>{};
    final data = _serviceData();
    final current = data[field];
    final label = _humanize(field);
    if (selector['boolean'] is Map || selector.containsKey('boolean')) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: current == true,
        onChanged: (value) => _setServiceDataValue(field, value),
      );
    }
    final select = selector['select'];
    if (select is Map && select['options'] is List) {
      final options = (select['options'] as List)
          .map((option) {
            if (option is Map) {
              final value = (option['value'] ?? option['id'])?.toString() ?? '';
              final text = (option['label'] ?? option['name'] ?? value)
                  .toString();
              return MapEntry(value, text);
            }
            final text = option.toString();
            return MapEntry(text, text);
          })
          .where((option) => option.key.isNotEmpty)
          .toList();
      final values = options.map((option) => option.key).toSet().toList();
      final selected = current?.toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          initialValue: values.contains(selected) ? selected : null,
          decoration: InputDecoration(labelText: label),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option.key,
                  child: Text(option.value),
                ),
              )
              .toList(),
          onChanged: (value) => _setServiceDataValue(field, value),
        ),
      );
    }
    final number = selector['number'];
    final isNumber = number is Map || selector.containsKey('number');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: current?.toString() ?? '',
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) => _setServiceDataValue(field, value),
      ),
    );
  }

  Widget _field(String field) {
    if (field == 'server') return _serverField();
    if (_type == 'api-call-service' && field == 'action') {
      return _serviceField();
    }
    if (_isEntityField(field)) return _selectionField(field);
    final value = _draft[field];
    if (value is bool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: value,
          title: Text(_label(field)),
          onChanged: (next) => _set(field, next),
        ),
      );
    }
    final options = _staticOptions(field);
    if (options.isNotEmpty) return _optionField(field);
    return _textField(field);
  }

  TextInputType _keyboardType(dynamic value) {
    if (value is num) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    final scalarFields = nodeEditorFields(_draft)
        .where(
          (field) => !_isHiddenByNativeField(field) && !_isEntityField(field),
        )
        .toList();
    final targetFields = <String>{
      ...nodeEditorFields(_draft).where(_isEntityField),
      ...nodeStructuredFields(_draft).where(_isEntityField),
    }.toList();
    final structuredFields = nodeStructuredFields(_draft)
        .where((field) => !_isEntityMapField(field) && !_isEntityField(field))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.86,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.home_work_outlined,
                    color: RivlenColors.wine,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '编辑 Home Assistant 节点',
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
              const SizedBox(height: 12),
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
                    if (_draft['entities'] is Map) _entityMapField(),
                    ...scalarFields.map(_field),
                    _serviceDataFields(),
                    ...targetFields.map(_selectionField),
                    ...structuredFields.map(
                      (field) => Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: _HaSelectionTile(
                          icon: Icons.data_object_rounded,
                          title: _label(field),
                          subtitle: '查看并编辑配置',
                          onTap: () => _editJsonField(field),
                        ),
                      ),
                    ),
                    _HaSelectionTile(
                      icon: Icons.data_object_rounded,
                      title: '高级配置',
                      subtitle: '编辑未覆盖的完整节点字段',
                      onTap: () => _editJsonFieldForNode(),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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

  Future<void> _editJsonFieldForNode() async {
    _applyControllers();
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(_draft),
    );
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
            title: const Text('高级配置'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: controller,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map) throw const FormatException();
      final next = Map<String, dynamic>.from(decoded);
      if (next['id']?.toString() != _draft['id']?.toString() ||
          next['type']?.toString() != _draft['type']?.toString() ||
          next['z']?.toString() != _draft['z']?.toString()) {
        throw const FormatException();
      }
      setState(() {
        _draft = next;
        _name.text = _draft['name']?.toString() ?? '';
        _syncControllers();
      });
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('节点 JSON 无效或修改了受保护字段')));
    }
  }
}

class _HaSelectionTile extends StatelessWidget {
  const _HaSelectionTile({
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
                    maxLines: 2,
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
