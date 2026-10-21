class NodeEditorSchema {
  const NodeEditorSchema({
    this.labels = const <String, String>{},
    this.fieldOrder = const <String>[],
  });

  final Map<String, String> labels;
  final List<String> fieldOrder;

  String? labelFor(String field) {
    final value = labels[field]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
