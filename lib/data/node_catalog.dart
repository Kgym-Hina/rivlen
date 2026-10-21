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

String nodeTitle(FlowNode node) =>
    (node['name'] as String?)?.trim().isNotEmpty == true
    ? (node['name'] as String).trim()
    : nodeKinds
              .where((item) => item.type == node['type'])
              .map((item) => item.title)
              .firstOrNull ??
          (node['type']?.toString() ?? 'Node');

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
  return nodeKinds
          .where((item) => item.type == type)
          .map((item) => item.title)
          .firstOrNull ??
      type;
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
