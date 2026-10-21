import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flow_bundle.dart';
import '../theme.dart';

class NodeKind {
  const NodeKind(this.type, this.title, this.category, this.description);

  final String type;
  final String title;
  final String category;
  final String description;
}

const nodeKinds = <NodeKind>[
  NodeKind('inject', 'Inject', 'Input', '按需或按计划触发一条消息'),
  NodeKind('catch', 'Catch', 'Input', '捕获流程中的错误'),
  NodeKind('complete', 'Complete', 'Input', '在节点完成时触发'),
  NodeKind('http in', 'HTTP In', 'Input', '接收 HTTP 请求'),
  NodeKind('mqtt in', 'MQTT In', 'Input', '订阅 MQTT 主题'),
  NodeKind('link in', 'Link In', 'Input', '从其他流程接收消息'),
  NodeKind('function', 'Function', 'Function', '运行 JavaScript 处理消息'),
  NodeKind('change', 'Change', 'Function', '设置、移动或删除消息属性'),
  NodeKind('switch', 'Switch', 'Function', '按条件将消息分流'),
  NodeKind('template', 'Template', 'Function', '使用模板生成文本'),
  NodeKind('delay', 'Delay', 'Function', '延迟或限制消息速率'),
  NodeKind('http request', 'HTTP Request', 'Network', '发送 HTTP 请求'),
  NodeKind('mqtt out', 'MQTT Out', 'Network', '向 MQTT 主题发布消息'),
  NodeKind('link out', 'Link Out', 'Network', '将消息发送到其他流程'),
  NodeKind('debug', 'Debug', 'Output', '查看消息内容'),
  NodeKind('http response', 'HTTP Response', 'Output', '返回 HTTP 响应'),
  NodeKind('comment', 'Comment', 'Other', '在画布上添加说明'),
];

final _random = Random.secure();

String createNodeId() =>
    List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();

String createLocalId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}${List.generate(4, (_) => _random.nextInt(16).toRadixString(16)).join()}';

String nodeTitle(FlowNode node) {
  final name = node['name']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final label = node['label']?.toString().trim() ?? '';
  if (label.isNotEmpty) return label;
  return nodeTypeLabel(node['type']?.toString() ?? 'Node');
}

String nodeTypeLabel(String type) {
  final known = nodeKinds
      .where((item) => item.type == type)
      .map((item) => item.title)
      .firstOrNull;
  if (known != null) return known;
  final words = type
      .replaceAll(RegExp(r'([a-z0-9])([A-Z])'), r'$1 $2')
      .replaceAll(RegExp(r'[-_.]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
  return words.isEmpty ? 'Node' : words;
}

String nodeSubtitle(FlowNode node) {
  final type = node['type']?.toString() ?? '';
  if (type == 'inject' && node['repeat']?.toString().isNotEmpty == true) {
    return '每 ${node['repeat']} 秒';
  }
  if (type == 'http request') {
    final method = node['method']?.toString() ?? 'GET';
    return '$method  ${node['url']?.toString() ?? ''}';
  }
  if (type == 'mqtt in' || type == 'mqtt out') {
    return node['topic']?.toString().isNotEmpty == true
        ? node['topic'].toString()
        : '未设置主题';
  }
  final domain = node['domain']?.toString().trim() ?? '';
  final service = node['service']?.toString().trim() ?? '';
  final action = node['action']?.toString().trim() ?? '';
  final entity = _firstNonEmpty([
    node['entityId'],
    node['entity_id'],
    node['entity'],
    node['deviceId'],
    node['device_id'],
    node['topic'],
    node['url'],
    node['path'],
    node['property'],
  ]);
  if (domain.isNotEmpty && service.isNotEmpty) return '$domain.$service';
  if (action.isNotEmpty) return action;
  if (entity != null) return entity;
  final detail = _firstScalarDetail(node);
  return detail ?? nodeTypeLabel(type);
}

String? _firstNonEmpty(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return null;
}

String? _firstScalarDetail(FlowNode node) {
  const ignored = {'id', 'type', 'z', 'x', 'y', 'wires', 'name', 'label'};
  for (final entry in node.entries) {
    if (ignored.contains(entry.key)) continue;
    final value = entry.value;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

int nodeOutputCount(FlowNode node) {
  if (node['wires'] is List) return (node['wires'] as List).length;
  return int.tryParse(node['outputs']?.toString() ?? '') ?? 0;
}

bool nodeHasInput(FlowNode node) => !const {
  'inject',
  'catch',
  'complete',
  'link in',
  'http in',
  'mqtt in',
  'comment',
}.contains(node['type']);

bool nodeHasOutput(FlowNode node) => !const {
  'debug',
  'http response',
  'link out',
  'mqtt out',
  'comment',
}.contains(node['type']);

RivlenNodeColor nodeColor(String type) {
  if (const {'inject', 'catch', 'complete', 'link in'}.contains(type)) {
    return const RivlenNodeColor(RivlenColors.amber, 'I');
  }
  if (const {
    'function',
    'switch',
    'change',
    'delay',
    'template',
  }.contains(type)) {
    return const RivlenNodeColor(RivlenColors.blue, 'ƒ');
  }
  if (const {'debug', 'http response', 'link out'}.contains(type)) {
    return const RivlenNodeColor(RivlenColors.green, '↗');
  }
  if (const {'http request', 'mqtt in', 'mqtt out', 'http in'}.contains(type)) {
    return const RivlenNodeColor(RivlenColors.purple, '↔');
  }
  if (type == 'comment') return const RivlenNodeColor(RivlenColors.muted, '·');
  return const RivlenNodeColor(RivlenColors.wine, 'N');
}

class RivlenNodeColor {
  const RivlenNodeColor(this.color, this.glyph);
  final Color color;
  final String glyph;
}

FlowNode createNode(String type, String tabId, double x, double y) {
  final id = createNodeId();
  final base = <String, dynamic>{
    'id': id,
    'type': type,
    'z': tabId,
    'name': '',
    'x': x.round(),
    'y': y.round(),
  };
  switch (type) {
    case 'inject':
      return {
        ...base,
        'props': [
          {'p': 'payload'},
          {'p': 'topic', 'vt': 'str'},
        ],
        'repeat': '',
        'crontab': '',
        'once': false,
        'onceDelay': 0.1,
        'topic': '',
        'payload': '',
        'payloadType': 'date',
        'wires': [[]],
      };
    case 'debug':
      return {
        ...base,
        'active': true,
        'tosidebar': true,
        'console': false,
        'tostatus': false,
        'complete': 'payload',
        'targetType': 'msg',
        'statusVal': '',
        'statusType': 'auto',
        'wires': [],
      };
    case 'function':
      return {
        ...base,
        'func': 'return msg;',
        'outputs': 1,
        'noerr': 0,
        'initialize': '',
        'finalize': '',
        'libs': [],
        'wires': [[]],
      };
    case 'switch':
      return {
        ...base,
        'property': 'payload',
        'propertyType': 'msg',
        'rules': [
          {'t': 'eq', 'v': '', 'vt': 'str'},
        ],
        'checkall': 'true',
        'repair': false,
        'outputs': 1,
        'wires': [[]],
      };
    case 'change':
      return {
        ...base,
        'rules': [],
        'action': '',
        'property': '',
        'from': '',
        'to': '',
        'reg': false,
        'wires': [[]],
      };
    case 'delay':
      return {
        ...base,
        'pauseType': 'delay',
        'timeout': '5',
        'timeoutUnits': 'seconds',
        'rate': '1',
        'nbRateUnits': '1',
        'rateUnits': 'second',
        'randomFirst': '1',
        'randomLast': '5',
        'randomUnits': 'seconds',
        'drop': false,
        'wires': [[]],
      };
    case 'template':
      return {
        ...base,
        'field': 'payload',
        'fieldType': 'msg',
        'format': 'handlebars',
        'syntax': 'mustache',
        'template': '',
        'output': 'str',
        'wires': [[]],
      };
    case 'http request':
      return {
        ...base,
        'method': 'GET',
        'ret': 'txt',
        'url': '',
        'tls': '',
        'persist': false,
        'proxy': '',
        'insecureHTTPParser': false,
        'senderr': false,
        'wires': [[]],
      };
    case 'mqtt in':
      return {
        ...base,
        'topic': '',
        'qos': '2',
        'datatype': 'auto',
        'broker': '',
        'nl': false,
        'rap': true,
        'rh': 0,
        'wires': [[]],
      };
    case 'mqtt out':
      return {
        ...base,
        'topic': '',
        'qos': '',
        'retain': '',
        'broker': '',
        'wires': [],
      };
    case 'http in':
      return {
        ...base,
        'url': '/api',
        'method': 'get',
        'upload': false,
        'swaggerDoc': '',
        'wires': [[]],
      };
    case 'http response':
      return {...base, 'statusCode': '', 'headers': {}, 'wires': []};
    case 'link in':
      return {
        ...base,
        'links': [],
        'wires': [[]],
      };
    case 'link out':
      return {...base, 'mode': 'link', 'links': [], 'wires': []};
    case 'catch':
      return {
        ...base,
        'scope': null,
        'uncaught': false,
        'wires': [[]],
      };
    case 'complete':
      return {
        ...base,
        'scope': [''],
        'uncaught': false,
        'wires': [[]],
      };
    case 'comment':
      return {...base, 'name': '说明', 'info': '', 'wires': []};
    default:
      return {
        ...base,
        'wires': [[]],
      };
  }
}

List<String> editableFields(FlowNode node) {
  switch (node['type']) {
    case 'inject':
      return ['topic', 'payload', 'repeat'];
    case 'function':
      return ['outputs'];
    case 'switch':
      return ['property'];
    case 'delay':
      return ['timeout', 'timeoutUnits'];
    case 'template':
      return ['field'];
    case 'http request':
      return ['method', 'url'];
    case 'http in':
      return ['method', 'url'];
    case 'mqtt in':
    case 'mqtt out':
      return ['topic', 'qos'];
    default:
      return [];
  }
}

const _nodeEditorStructuralFields = {'id', 'type', 'z', 'x', 'y', 'wires'};
const _nodeEditorSpecialFields = {'func', 'template', 'info'};

/// Returns scalar properties that can be edited without knowing a node's
/// package in advance. This lets Home Assistant and third-party nodes expose
/// their ordinary string, number, and boolean settings automatically.
List<String> nodeEditorFields(FlowNode node) {
  final fields = <String>[];
  void add(String field) {
    if (fields.contains(field)) return;
    if (_nodeEditorStructuralFields.contains(field) ||
        (_nodeEditorSpecialFields.contains(field) &&
            complexField(node) == field) ||
        field == 'name' ||
        field.startsWith('__')) {
      return;
    }
    final value = node[field];
    if (value is String || value is num || value is bool) fields.add(field);
  }

  for (final field in editableFields(node)) {
    add(field);
  }
  for (final field in node.keys) {
    add(field);
  }
  return fields;
}

/// Returns structured properties (arrays, objects, and null values) that are
/// edited through a field-level JSON editor rather than the whole node JSON.
List<String> nodeStructuredFields(FlowNode node) {
  final fields = <String>[];
  for (final field in node.keys) {
    if (_nodeEditorStructuralFields.contains(field) ||
        (_nodeEditorSpecialFields.contains(field) &&
            complexField(node) == field) ||
        field == 'name' ||
        field.startsWith('__')) {
      continue;
    }
    final value = node[field];
    if (value is List || value is Map || value == null) fields.add(field);
  }
  return fields;
}

String? complexField(FlowNode node) {
  switch (node['type']) {
    case 'function':
      return 'func';
    case 'template':
      return 'template';
    case 'comment':
      return 'info';
    default:
      return null;
  }
}
