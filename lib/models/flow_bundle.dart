import 'dart:convert';

typedef FlowNode = Map<String, dynamic>;

List<FlowNode> cloneNodes(List<FlowNode> nodes) =>
    (jsonDecode(jsonEncode(nodes)) as List<dynamic>)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();

class FlowBundle {
  const FlowBundle({
    required this.nodes,
    this.revision,
    this.apiV2 = true,
    this.envelope = const {},
  });

  final List<FlowNode> nodes;
  final String? revision;
  final bool apiV2;

  /// Unknown top-level fields are kept intact when a flow is deployed again.
  final Map<String, dynamic> envelope;

  factory FlowBundle.fromResponse(dynamic payload) {
    if (payload is List) {
      return FlowBundle(
        nodes: payload
            .whereType<Map>()
            .map((node) => Map<String, dynamic>.from(node))
            .toList(),
        apiV2: false,
      );
    }

    if (payload is! Map || payload['flows'] is! List) {
      throw const FormatException('Unexpected response from /flows.');
    }

    final envelope = Map<String, dynamic>.from(payload)
      ..remove('flows')
      ..remove('rev');
    return FlowBundle(
      nodes: (payload['flows'] as List)
          .whereType<Map>()
          .map((node) => Map<String, dynamic>.from(node))
          .toList(),
      revision: payload['rev']?.toString(),
      apiV2: payload['rev'] != null,
      envelope: envelope,
    );
  }

  FlowBundle copyWith({
    List<FlowNode>? nodes,
    String? revision,
    bool? apiV2,
    Map<String, dynamic>? envelope,
  }) => FlowBundle(
    nodes: nodes ?? this.nodes,
    revision: revision ?? this.revision,
    apiV2: apiV2 ?? this.apiV2,
    envelope: envelope ?? this.envelope,
  );

  Map<String, dynamic> toRequestBody() => {
    ...envelope,
    if (apiV2 && revision != null) 'rev': revision,
    'flows': nodes,
  };

  List<Map<String, dynamic>> toLegacyBody() => nodes;

  String canonicalJson() => jsonEncode(nodes);
}

class FlowConflictException implements Exception {
  const FlowConflictException();

  @override
  String toString() => 'The flow changed on the Node-RED instance.';
}

class NodeRedApiException implements Exception {
  const NodeRedApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
