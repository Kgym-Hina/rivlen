import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/node_catalog.dart';
import '../models/flow_bundle.dart';
import '../theme.dart';

class FlowLink {
  const FlowLink(this.sourceId, this.outputIndex, this.targetId);
  final String sourceId;
  final int outputIndex;
  final String targetId;

  @override
  bool operator ==(Object other) =>
      other is FlowLink &&
      sourceId == other.sourceId &&
      outputIndex == other.outputIndex &&
      targetId == other.targetId;

  @override
  int get hashCode => Object.hash(sourceId, outputIndex, targetId);
}

class FlowCanvas extends StatefulWidget {
  const FlowCanvas({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.selectedLink,
    required this.onSelectNode,
    required this.onClearSelection,
    required this.onEditNode,
    required this.onMoveNode,
    required this.onMoveEnd,
    required this.onConnect,
    required this.onAddAtWireEnd,
    required this.onAddAtPoint,
    required this.onSelectLink,
    required this.onFitBounds,
  });

  final List<FlowNode> nodes;
  final String? selectedNodeId;
  final FlowLink? selectedLink;
  final ValueChanged<String> onSelectNode;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onEditNode;
  final void Function(String id, Offset delta) onMoveNode;
  final VoidCallback onMoveEnd;
  final void Function(String source, int outputIndex, String target) onConnect;
  final void Function(String source, int outputIndex, Offset worldPoint)
  onAddAtWireEnd;
  final ValueChanged<Offset> onAddAtPoint;
  final ValueChanged<FlowLink> onSelectLink;
  final VoidCallback onFitBounds;

  @override
  State<FlowCanvas> createState() => FlowCanvasState();
}

const _compactCoordinateScale = 1.45;
const _junctionDiameter = 16.0;
const _junctionPortOffset = 19.0;
const _junctionPortHitRadius = 13.0;

class FlowCanvasState extends State<FlowCanvas> {
  static const _minimumScale = 0.38;
  static const _maximumScale = 2.1;
  // Node-RED stores desktop-sized coordinates. On a phone, expanding the
  // coordinate distance before fitting the canvas keeps nodes and wires from
  // collapsing into one another while preserving the original flow values.
  double _scale = 1;
  Offset _translation = Offset.zero;
  Offset _lastLocal = Offset.zero;
  Offset _startLocal = Offset.zero;
  Offset _focalWorldAtPinch = Offset.zero;
  double _pinchStartScale = 1;
  double _pinchScaleAtStart = 1;
  bool _pinching = false;
  bool _moved = false;
  bool _moveStarted = false;
  bool _viewInitialized = false;
  bool _compactLayout = false;
  String? _dragNodeId;
  FlowLink? _pickedLink;
  _PortHit? _pickedPort;
  _PortHit? _wireSource;
  String? _pendingSourceId;
  int _pendingOutputIndex = 0;
  Offset? _previewPoint;
  DateTime? _lastTapAt;
  String? _lastTapNodeId;
  Offset? _lastTapWorld;
  Size? _viewportSize;

  double get _coordinateScale => _compactLayout ? _compactCoordinateScale : 1.0;

  Offset get worldCenter {
    final size = _viewportSize;
    return size == null
        ? Offset.zero
        : _toFlowWorld(_toWorld(size.center(Offset.zero)));
  }

  void resetView() {
    if (_viewportSize == null) return;
    final size = _viewportSize!;
    final positioned = _placedNodesFor(
      widget.nodes,
      compact: _compactLayout,
    ).where((item) => item.node['type'] != 'comment').toList(growable: false);
    if (positioned.isEmpty) {
      setState(() {
        _scale = 1;
        _translation = Offset(size.width * 0.12, size.height * 0.24);
        _viewInitialized = true;
      });
      return;
    }
    var minX = positioned.first.rect.left;
    var minY = positioned.first.rect.top;
    var maxX = positioned.first.rect.right;
    var maxY = positioned.first.rect.bottom;
    for (final item in positioned.skip(1)) {
      minX = math.min(minX, item.rect.left);
      minY = math.min(minY, item.rect.top);
      maxX = math.max(maxX, item.rect.right);
      maxY = math.max(maxY, item.rect.bottom);
    }
    const marginX = 160.0;
    const marginY = 140.0;
    final boundsWidth = (maxX - minX + marginX * 2).clamp(280.0, 3000.0);
    final boundsHeight = (maxY - minY + marginY * 2).clamp(220.0, 2200.0);
    final fitted = (size.width / boundsWidth).clamp(0.48, 1.15);
    final scale = fitted < size.height / boundsHeight
        ? fitted
        : (size.height / boundsHeight).clamp(0.48, 1.15);
    setState(() {
      _scale = scale.toDouble();
      _viewInitialized = true;
      _translation = Offset(
        size.width / 2 - (minX + maxX) / 2 * _scale,
        size.height / 2 - (minY + maxY) / 2 * _scale,
      );
    });
  }

  void focusNode(String id) {
    final size = _viewportSize;
    if (size == null) return;
    final item = _placedNodesFor(
      widget.nodes,
      compact: _compactLayout,
    ).where((entry) => entry.node['id'].toString() == id).firstOrNull;
    if (item == null) return;
    setState(
      () => _translation = size.center(Offset.zero) - item.rect.center * _scale,
    );
  }

  Offset _toWorld(Offset point) => (point - _translation) / _scale;

  Offset _toFlowWorld(Offset displayWorld) => displayWorld / _coordinateScale;

  _PortHit? _portAt(Offset local) {
    final placed = _placedNodesFor(widget.nodes, compact: _compactLayout);
    for (final item in placed.reversed) {
      final node = item.node;
      if (isJunctionNode(node)) {
        final input = _inputWorld(item);
        if ((_screen(input) - local).distance <= _junctionPortHitRadius) {
          return _PortHit(node['id'].toString(), 0, false);
        }
        final output = _outputWorld(item, 0);
        if ((_screen(output) - local).distance <= _junctionPortHitRadius) {
          return _PortHit(node['id'].toString(), 0, true);
        }
        continue;
      }
      final center = item.rect.center;
      if (nodeHasInput(node)) {
        final input = Offset(center.dx - item.rect.width / 2, center.dy);
        if ((_screen(input) - local).distance <= 27) {
          return _PortHit(node['id'].toString(), 0, false);
        }
      }
      final outputs = nodeOutputCount(node);
      if (outputs > 0 && nodeHasOutput(node)) {
        for (var index = 0; index < outputs; index++) {
          final output = Offset(
            center.dx + item.rect.width / 2,
            center.dy + _outputOffset(index, outputs),
          );
          if ((_screen(output) - local).distance <= 27) {
            return _PortHit(node['id'].toString(), index, true);
          }
        }
      }
    }
    return null;
  }

  Offset _screen(Offset world) => world * _scale + _translation;

  _PlacedNode? _nodeAt(Offset local) {
    final world = _toWorld(local);
    for (final item in _placedNodesFor(
      widget.nodes,
      compact: _compactLayout,
    ).reversed) {
      if (item.rect.inflate(8).contains(world)) return item;
    }
    return null;
  }

  FlowLink? _linkAt(Offset local) {
    final items = _placedNodesFor(widget.nodes, compact: _compactLayout);
    final byId = {for (final item in items) item.node['id'].toString(): item};
    for (final item in items.reversed) {
      final wires = item.node['wires'];
      if (wires is! List) continue;
      for (var output = 0; output < wires.length; output++) {
        final targets = wires[output];
        if (targets is! List) continue;
        for (final target in targets) {
          final to = byId[target?.toString()];
          if (to == null) continue;
          final fromPoint = _outputWorld(item, output);
          final toPoint = _inputWorld(to);
          final start = _screen(fromPoint);
          final end = _screen(toPoint);
          final path = _wirePath(start, end);
          for (var sample = 0; sample <= 20; sample++) {
            final point = path
                .computeMetrics()
                .first
                .getTangentForOffset(
                  path.computeMetrics().first.length * sample / 20,
                )
                ?.position;
            if (point != null && (point - local).distance < 14) {
              return FlowLink(
                item.node['id'].toString(),
                output,
                target.toString(),
              );
            }
          }
        }
      }
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final local = details.localFocalPoint;
    _startLocal = local;
    _lastLocal = local;
    _moved = false;
    _moveStarted = false;
    _pinching = false;
    _dragNodeId = null;
    _pickedPort = _portAt(local);
    _wireSource = null;
    _pickedLink = null;

    final port = _pickedPort;
    if (port != null && port.output) {
      _wireSource = port;
      return;
    }
    if (port != null && !port.output && _pendingSourceId != null) {
      _wireSource = _PortHit(_pendingSourceId!, _pendingOutputIndex, true);
      return;
    }
    // A junction is a draggable point on the wire. Pick it before testing
    // the nearby wire so tapping the dot never selects the underlying link.
    final junction = _nodeAt(local);
    if (junction != null && isJunctionNode(junction.node)) {
      _dragNodeId = junction.node['id'].toString();
      return;
    }
    final link = _linkAt(local);
    if (link != null) {
      _pickedLink = link;
      return;
    }
    final node = _nodeAt(local);
    if (node != null && (port == null || !port.output)) {
      _dragNodeId = node.node['id'].toString();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final local = details.localFocalPoint;
    if (details.pointerCount > 1) {
      if (!_pinching) {
        _pinching = true;
        _pinchStartScale = _scale;
        _pinchScaleAtStart = details.scale;
        _focalWorldAtPinch = _toWorld(local);
        _dragNodeId = null;
        _wireSource = null;
      }
      final factor = details.scale / _pinchScaleAtStart;
      final nextScale = (_pinchStartScale * factor).clamp(
        _minimumScale,
        _maximumScale,
      );
      setState(() {
        _scale = nextScale.toDouble();
        _translation = local - _focalWorldAtPinch * _scale;
        _lastLocal = local;
      });
      return;
    }
    if (_pinching) {
      _pinching = false;
      _lastLocal = local;
      _startLocal = local;
      return;
    }
    final delta = local - _lastLocal;
    if ((local - _startLocal).distance > 5) _moved = true;
    _lastLocal = local;

    if (_wireSource != null) {
      setState(() => _previewPoint = local);
      return;
    }
    if (_dragNodeId != null) {
      if (_moved) {
        final movement = _moveStarted ? delta : local - _startLocal;
        if (movement.distance > 0) {
          widget.onMoveNode(_dragNodeId!, movement / _scale / _coordinateScale);
        }
        _moveStarted = true;
      }
      return;
    }
    if (_pickedLink != null) return;
    if (delta.distance > 0) {
      setState(() => _translation += delta);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_pinching) {
      _pinching = false;
      _previewPoint = null;
      return;
    }
    final local = _lastLocal;
    if (_wireSource != null) {
      final source = _wireSource!;
      _previewPoint = null;
      if (_moved) {
        final endPort = _portAt(local);
        if (endPort != null &&
            !endPort.output &&
            endPort.nodeId != source.nodeId) {
          widget.onConnect(source.nodeId, source.outputIndex, endPort.nodeId);
          setState(() {
            _pendingSourceId = null;
            _wireSource = null;
          });
          return;
        }
        final endNode = _nodeAt(local);
        if (endNode == null) {
          widget.onAddAtWireEnd(
            source.nodeId,
            source.outputIndex,
            _toFlowWorld(_toWorld(local)),
          );
          setState(() {
            _pendingSourceId = null;
            _wireSource = null;
          });
          return;
        }
        setState(() {
          _pendingSourceId = source.nodeId;
          _pendingOutputIndex = source.outputIndex;
          _wireSource = null;
        });
        return;
      }
      if (_pickedPort != null && _pickedPort!.output) {
        setState(() {
          if (_pendingSourceId == source.nodeId &&
              _pendingOutputIndex == source.outputIndex) {
            _pendingSourceId = null;
          } else {
            _pendingSourceId = source.nodeId;
            _pendingOutputIndex = source.outputIndex;
          }
          _wireSource = null;
        });
        return;
      }
    }

    final port = _pickedPort;
    if (port != null && !port.output && _pendingSourceId != null) {
      widget.onConnect(_pendingSourceId!, _pendingOutputIndex, port.nodeId);
      setState(() {
        _pendingSourceId = null;
        _wireSource = null;
      });
      return;
    }

    if (!_moved && _pickedLink != null) {
      widget.onSelectLink(_pickedLink!);
      return;
    }
    if (_dragNodeId != null) {
      if (_moveStarted) {
        widget.onMoveEnd();
      } else {
        _handleTap(_dragNodeId, _toFlowWorld(_toWorld(local)));
      }
      return;
    }
    if (!_moved) _handleTap(null, _toFlowWorld(_toWorld(local)));
    if (mounted) {
      setState(() {
        _wireSource = null;
        _previewPoint = null;
      });
    }
  }

  void _handleTap(String? nodeId, Offset world) {
    final now = DateTime.now();
    final sameTarget =
        nodeId == _lastTapNodeId &&
        (_lastTapWorld == null || (_lastTapWorld! - world).distance < 42);
    final isDoubleTap =
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < const Duration(milliseconds: 380) &&
        sameTarget;
    _lastTapAt = now;
    _lastTapNodeId = nodeId;
    _lastTapWorld = world;
    if (nodeId != null) {
      widget.onSelectNode(nodeId);
      if (isDoubleTap) widget.onEditNode(nodeId);
    } else {
      widget.onClearSelection();
      if (isDoubleTap) widget.onAddAtPoint(world);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
      final compact = constraints.maxWidth < 700;
      if (_compactLayout != compact) {
        _compactLayout = compact;
        _viewInitialized = false;
      }
      if (!_viewInitialized && widget.nodes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_viewInitialized) resetView();
        });
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: CustomPaint(
              painter: _FlowCanvasPainter(
                nodes: widget.nodes,
                scale: _scale,
                translation: _translation,
                selectedNodeId: widget.selectedNodeId,
                selectedLink: widget.selectedLink,
                pendingSourceId: _pendingSourceId,
                pendingOutputIndex: _pendingOutputIndex,
                previewSource: _wireSource,
                previewPoint: _previewPoint,
                compactLayout: _compactLayout,
              ),
            ),
          ),
          if (widget.nodes.isEmpty)
            Positioned(
              left: 24,
              right: 24,
              top: constraints.maxHeight * 0.32,
              child: const _EmptyCanvasHint(),
            ),
          Positioned(
            right: 17,
            bottom: 17,
            child: Material(
              color: RivlenColors.surface,
              borderRadius: BorderRadius.circular(17),
              elevation: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '缩小',
                    onPressed: () => _zoom(0.83),
                    icon: Icon(Icons.remove_rounded, size: 20),
                  ),
                  Container(width: 1, height: 18, color: RivlenColors.line),
                  IconButton(
                    tooltip: '适应画布',
                    onPressed: widget.onFitBounds,
                    icon: Icon(Icons.center_focus_strong_rounded, size: 17),
                  ),
                  Container(width: 1, height: 18, color: RivlenColors.line),
                  IconButton(
                    tooltip: '放大',
                    onPressed: () => _zoom(1.2),
                    icon: Icon(Icons.add_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (_pendingSourceId != null)
            Positioned(
              left: 14,
              right: 14,
              top: 14,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: RivlenColors.ink.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '选择一个输入端口',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  void _zoom(double factor) {
    final size = _viewportSize;
    if (size == null) return;
    final anchor = size.center(Offset.zero);
    final world = _toWorld(anchor);
    setState(() {
      _scale = (_scale * factor).clamp(_minimumScale, _maximumScale);
      _translation = anchor - world * _scale;
    });
  }
}

class _PortHit {
  const _PortHit(this.nodeId, this.outputIndex, this.output);
  final String nodeId;
  final int outputIndex;
  final bool output;
}

class _PlacedNode {
  const _PlacedNode(this.node, this.rect, this.index);
  final FlowNode node;
  final Rect rect;
  final int index;
}

List<_PlacedNode> _placedNodesFor(
  List<FlowNode> nodes, {
  bool compact = false,
}) {
  final placed = <_PlacedNode>[];
  // Collision avoidance is for cards only. A junction is intentionally
  // allowed to sit on a wire and must not push nearby cards away.
  final collisionPeers = <_PlacedNode>[];
  for (var index = 0; index < nodes.length; index++) {
    final node = nodes[index];
    final junction = isJunctionNode(node);
    final x = node['x'] is num
        ? (node['x'] as num).toDouble()
        : 180.0 + index * 220;
    final y = node['y'] is num
        ? (node['y'] as num).toDouble()
        : 180.0 + (index % 3) * 100;
    final cardSize = _nodeCardSize(node);
    final width = cardSize.width;
    final height = cardSize.height;
    final requested = Offset(
      compact ? x * _compactCoordinateScale : x,
      compact ? y * _compactCoordinateScale : y,
    );
    final center = compact
        ? junction
              ? requested
              : _collisionFreeCenter(requested, width, height, collisionPeers)
        : requested;
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final item = _PlacedNode(node, rect, index);
    placed.add(item);
    if (!junction) collisionPeers.add(item);
  }
  return placed;
}

Offset _collisionFreeCenter(
  Offset requested,
  double width,
  double height,
  List<_PlacedNode> placed,
) {
  const gapX = 28.0;
  const gapY = 24.0;
  const clearance = 8.0;
  var candidate = requested;
  for (var attempt = 0; attempt < 64; attempt++) {
    final rect = Rect.fromCenter(
      center: candidate,
      width: width,
      height: height,
    );
    final collisions = placed
        .where((item) => item.rect.inflate(clearance / 2).overlaps(rect))
        .toList(growable: false);
    if (collisions.isEmpty) return candidate;

    final lowest = collisions.reduce(
      (a, b) => a.rect.bottom > b.rect.bottom ? a : b,
    );
    candidate = Offset(
      candidate.dx,
      math.max(candidate.dy, lowest.rect.bottom + gapY + height / 2),
    );
    if (attempt == 8) {
      candidate = Offset(requested.dx + width + gapX, requested.dy);
    }
  }
  return candidate;
}

Offset _inputWorld(_PlacedNode item) => isJunctionNode(item.node)
    ? item.rect.center.translate(-_junctionPortOffset, 0)
    : Offset(item.rect.left, item.rect.center.dy);

Offset _outputWorld(_PlacedNode item, int outputIndex) =>
    isJunctionNode(item.node)
    ? item.rect.center.translate(_junctionPortOffset, 0)
    : Offset(
        item.rect.right,
        item.rect.center.dy +
            _outputOffset(outputIndex, nodeOutputCount(item.node)),
      );

double _outputOffset(int index, int count) {
  if (count <= 1) return 0;
  return (index - (count - 1) / 2) * 12;
}

Path _wirePath(Offset start, Offset end) {
  final dx = (end.dx - start.dx).abs();
  final bend = dx * 0.48 < 78 ? 78.0 : dx * 0.48;
  return Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(start.dx + bend, start.dy, end.dx - bend, end.dy, end.dx, end.dy);
}

Size _nodeCardSize(FlowNode node) {
  if (isJunctionNode(node)) return const Size.square(_junctionDiameter);
  final type = node['type']?.toString() ?? '';
  if (type == 'comment') return const Size(176, 40);
  final title = nodeTitle(node);
  final rawSubtitle = nodeSubtitle(node);
  final subtitle = rawSubtitle == nodeTypeLabel(type) ? '' : rawSubtitle;
  final textLength = math.max(title.runes.length, subtitle.runes.length);
  final width = (132 + textLength * 5.2).clamp(146.0, 220.0).toDouble();
  return Size(width, subtitle.isEmpty ? 44 : 52);
}

String _displayNodeSubtitle(FlowNode node) {
  final type = node['type']?.toString() ?? '';
  final subtitle = nodeSubtitle(node);
  return subtitle == nodeTypeLabel(type) ? '' : subtitle;
}

class _FlowCanvasPainter extends CustomPainter {
  const _FlowCanvasPainter({
    required this.nodes,
    required this.scale,
    required this.translation,
    required this.selectedNodeId,
    required this.selectedLink,
    required this.pendingSourceId,
    required this.pendingOutputIndex,
    required this.previewSource,
    required this.previewPoint,
    required this.compactLayout,
  });

  final List<FlowNode> nodes;
  final double scale;
  final Offset translation;
  final String? selectedNodeId;
  final FlowLink? selectedLink;
  final String? pendingSourceId;
  final int pendingOutputIndex;
  final _PortHit? previewSource;
  final Offset? previewPoint;
  final bool compactLayout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(RivlenColors.canvas, BlendMode.src);
    _drawGrid(canvas, size);
    final items = _placedNodesFor(nodes, compact: compactLayout);
    final byId = {for (final item in items) item.node['id'].toString(): item};
    canvas.save();
    canvas.translate(translation.dx, translation.dy);
    canvas.scale(scale);
    for (final item in items) {
      _drawWires(canvas, item, byId);
    }
    if (previewSource != null && previewPoint != null) {
      final item = byId[previewSource!.nodeId];
      if (item != null) {
        final start = _outputWorld(item, previewSource!.outputIndex);
        final previewWorld = (previewPoint! - translation) / scale;
        final path = _wirePath(start, previewWorld);
        canvas.drawPath(
          path,
          Paint()
            ..color = RivlenColors.coral
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (final item in items) {
      _drawNode(canvas, item);
    }
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    const spacing = 24.0;
    final paint = Paint()..color = RivlenColors.line.withValues(alpha: 0.58);
    for (double x = 12; x < size.width; x += spacing) {
      for (double y = 12; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  void _drawWires(
    Canvas canvas,
    _PlacedNode item,
    Map<String, _PlacedNode> byId,
  ) {
    final wires = item.node['wires'];
    if (wires is! List) return;
    for (var output = 0; output < wires.length; output++) {
      final targets = wires[output];
      if (targets is! List) continue;
      for (final target in targets) {
        final destination = byId[target?.toString()];
        if (destination == null) continue;
        final link = FlowLink(
          item.node['id'].toString(),
          output,
          target.toString(),
        );
        final path = _wirePath(
          _outputWorld(item, output),
          _inputWorld(destination),
        );
        final isSelected = link == selectedLink;
        canvas.drawPath(
          path,
          Paint()
            ..color = isSelected
                ? RivlenColors.coral
                : RivlenColors.muted.withValues(alpha: 0.72)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 3.2 : 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawNode(Canvas canvas, _PlacedNode item) {
    final node = item.node;
    final rect = item.rect;
    if (isJunctionNode(node)) {
      _drawJunction(canvas, item);
      return;
    }
    final type = node['type']?.toString() ?? '';
    final color = nodeColor(type).color;
    final selected = node['id']?.toString() == selectedNodeId;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = RivlenColors.ink.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    final cardFill = type == 'comment'
        ? RivlenColors.surface
        : Color.alphaBlend(color.withValues(alpha: 0.14), RivlenColors.surface);
    canvas.drawRRect(rrect, Paint()..color = cardFill);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(rect.left, rect.top, 4, rect.height),
        topLeft: const Radius.circular(8),
        bottomLeft: const Radius.circular(8),
      ),
      Paint()..color = color,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = selected ? RivlenColors.coral : color.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.7 : 0.8,
    );
    final iconSize = math.min(28.0, rect.height - 12);
    final iconRect = Rect.fromLTWH(
      rect.left + 10,
      rect.top + (rect.height - iconSize) / 2,
      iconSize,
      iconSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(iconRect, const Radius.circular(7)),
      Paint()..color = color.withValues(alpha: 0.14),
    );
    _drawCenteredText(
      canvas,
      nodeColor(type).glyph,
      iconRect,
      color,
      18,
      fontWeight: FontWeight.w700,
    );
    final title = nodeTitle(node);
    final subtitle = _displayNodeSubtitle(node);
    final textLeft = rect.left + 47;
    final textWidth = rect.right - textLeft - 9;
    final titleTop = subtitle.isEmpty
        ? rect.top + (rect.height - 15) / 2
        : rect.top + 9;
    _drawText(
      canvas,
      title,
      Offset(textLeft, titleTop),
      RivlenColors.ink,
      12,
      fontWeight: FontWeight.w600,
      width: textWidth,
      maxLines: 1,
    );
    if (subtitle.isNotEmpty) {
      _drawText(
        canvas,
        subtitle,
        Offset(textLeft, rect.top + 28),
        RivlenColors.muted,
        9.5,
        width: textWidth,
        maxLines: 1,
      );
    }
    if (nodeHasInput(node)) {
      _drawPort(canvas, Offset(rect.left, rect.center.dy), RivlenColors.wine);
    }
    final outputs = nodeOutputCount(node);
    if (nodeHasOutput(node)) {
      for (var index = 0; index < outputs; index++) {
        final port = Offset(
          rect.right,
          rect.center.dy + _outputOffset(index, outputs),
        );
        _drawPort(
          canvas,
          port,
          pendingSourceId == node['id'] && pendingOutputIndex == index
              ? RivlenColors.coral
              : RivlenColors.wine,
        );
      }
    }
  }

  void _drawJunction(Canvas canvas, _PlacedNode item) {
    final center = item.rect.center;
    final input = _inputWorld(item);
    final output = _outputWorld(item, 0);
    final selected = item.node['id']?.toString() == selectedNodeId;
    // A junction is a draggable center with two separate wire handles. The
    // handles stay on the wire while the larger center remains easy to move.
    _drawJunctionPort(canvas, input, RivlenColors.wine);
    _drawJunctionPort(
      canvas,
      output,
      pendingSourceId == item.node['id']
          ? RivlenColors.coral
          : RivlenColors.wine,
    );
    canvas.drawCircle(
      center,
      selected ? 11 : 10,
      Paint()..color = RivlenColors.surface,
    );
    canvas.drawCircle(
      center,
      selected ? 8.5 : 7.5,
      Paint()..color = selected ? RivlenColors.coral : RivlenColors.wine,
    );
    if (selected) {
      canvas.drawCircle(
        center,
        11.5,
        Paint()
          ..color = RivlenColors.coral.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawJunctionPort(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 6.5, Paint()..color = RivlenColors.surface);
    canvas.drawCircle(center, 4.2, Paint()..color = color);
    canvas.drawCircle(center, 1.4, Paint()..color = RivlenColors.surface);
  }

  void _drawPort(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 7.5, Paint()..color = RivlenColors.surface);
    canvas.drawCircle(
      center,
      5.2,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 1.8, Paint()..color = color);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    required double width,
    FontWeight fontWeight = FontWeight.w400,
    TextAlign align = TextAlign.left,
    int maxLines = 2,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
      textAlign: align,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Rect rect,
    Color color,
    double fontSize, {
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(minWidth: rect.width, maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(rect.left, rect.top + (rect.height - painter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FlowCanvasPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.scale != scale ||
      oldDelegate.translation != translation ||
      oldDelegate.selectedNodeId != selectedNodeId ||
      oldDelegate.selectedLink != selectedLink ||
      oldDelegate.pendingSourceId != pendingSourceId ||
      oldDelegate.previewPoint != previewPoint ||
      oldDelegate.compactLayout != compactLayout;
}

class _EmptyCanvasHint extends StatelessWidget {
  const _EmptyCanvasHint();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: RivlenColors.surface,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(Icons.add_rounded, color: RivlenColors.wine, size: 25),
        ),
        const SizedBox(height: 13),
        Text(
          '双击空白处添加节点',
          style: TextStyle(
            color: RivlenColors.ink,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '也可以从底部菜单添加',
          style: TextStyle(color: RivlenColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
