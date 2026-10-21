import 'dart:convert';

/// The read-only data exposed by the Home Assistant Node-RED server config.
///
/// Node-RED already has the Home Assistant access token, so the mobile client
/// never needs to know it.  This model intentionally keeps the service schema
/// as JSON-like maps: Home Assistant adds selectors over time and preserving
/// the unknown selector fields lets the editor remain compatible with newer
/// integrations.
class HomeAssistantCatalog {
  const HomeAssistantCatalog({
    this.entities = const <HomeAssistantEntity>[],
    this.services = const <HomeAssistantService>[],
    this.areas = const <HomeAssistantOption>[],
    this.devices = const <HomeAssistantOption>[],
    this.floors = const <HomeAssistantOption>[],
    this.labels = const <HomeAssistantOption>[],
    this.serverNames = const <String, String>{},
  });

  final List<HomeAssistantEntity> entities;
  final List<HomeAssistantService> services;
  final List<HomeAssistantOption> areas;
  final List<HomeAssistantOption> devices;
  final List<HomeAssistantOption> floors;
  final List<HomeAssistantOption> labels;
  final Map<String, String> serverNames;

  bool get isEmpty =>
      entities.isEmpty &&
      services.isEmpty &&
      areas.isEmpty &&
      devices.isEmpty &&
      floors.isEmpty &&
      labels.isEmpty;

  List<String> get domains {
    final values = services.map((service) => service.domain).toSet().toList()
      ..sort();
    return values;
  }

  HomeAssistantCatalog merge(HomeAssistantCatalog other) {
    final entityById = <String, HomeAssistantEntity>{
      for (final entity in entities) entity.id: entity,
      for (final entity in other.entities) entity.id: entity,
    };
    final serviceById = <String, HomeAssistantService>{
      for (final service in services) service.key: service,
      for (final service in other.services) service.key: service,
    };
    return HomeAssistantCatalog(
      entities: entityById.values.toList()..sort(_compareEntities),
      services: serviceById.values.toList()..sort(_compareServices),
      areas: _mergeOptions(areas, other.areas),
      devices: _mergeOptions(devices, other.devices),
      floors: _mergeOptions(floors, other.floors),
      labels: _mergeOptions(labels, other.labels),
      serverNames: {...serverNames, ...other.serverNames},
    );
  }

  static List<HomeAssistantOption> _mergeOptions(
    List<HomeAssistantOption> first,
    List<HomeAssistantOption> second,
  ) {
    final values = <String, HomeAssistantOption>{
      for (final option in first) option.id: option,
      for (final option in second) option.id: option,
    };
    return values.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  static int _compareEntities(HomeAssistantEntity a, HomeAssistantEntity b) =>
      a.label.toLowerCase().compareTo(b.label.toLowerCase());

  static int _compareServices(HomeAssistantService a, HomeAssistantService b) =>
      a.key.compareTo(b.key);
}

class HomeAssistantEntity {
  const HomeAssistantEntity({required this.id, this.label = ''});

  final String id;
  final String label;

  String get displayName => label.trim().isEmpty ? id : '$label · $id';
}

class HomeAssistantOption {
  const HomeAssistantOption({required this.id, this.label = ''});

  final String id;
  final String label;

  String get displayName => label.trim().isEmpty ? id : '$label · $id';
}

class HomeAssistantService {
  const HomeAssistantService({
    required this.domain,
    required this.service,
    this.description = '',
    this.fields = const <String, dynamic>{},
    this.target = const <String, dynamic>{},
  });

  final String domain;
  final String service;
  final String description;
  final Map<String, dynamic> fields;
  final Map<String, dynamic> target;

  String get key => '$domain.$service';

  String get displayName => key;

  factory HomeAssistantService.fromJson(
    String domain,
    String service,
    dynamic raw,
  ) {
    final value = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    return HomeAssistantService(
      domain: domain,
      service: service,
      description: value['description']?.toString() ?? '',
      fields: value['fields'] is Map
          ? Map<String, dynamic>.from(value['fields'] as Map)
          : const {},
      target: value['target'] is Map
          ? Map<String, dynamic>.from(value['target'] as Map)
          : const {},
    );
  }
}

HomeAssistantCatalog homeAssistantCatalogFromResponses({
  dynamic entitiesPayload,
  dynamic servicesPayload,
  dynamic areasPayload,
  dynamic devicesPayload,
  dynamic floorsPayload,
  dynamic labelsPayload,
  String? serverId,
  String? serverName,
}) {
  final entities = <HomeAssistantEntity>[];
  if (entitiesPayload is List) {
    for (final value in entitiesPayload) {
      if (value is String && value.trim().isNotEmpty) {
        entities.add(HomeAssistantEntity(id: value.trim()));
      } else if (value is Map) {
        final id = (value['entity_id'] ?? value['id'])?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final label =
            (value['name'] ?? value['friendly_name'] ?? value['original_name'])
                ?.toString() ??
            '';
        entities.add(HomeAssistantEntity(id: id, label: label));
      }
    }
  }

  final services = <HomeAssistantService>[];
  if (servicesPayload is Map) {
    for (final domainEntry in servicesPayload.entries) {
      final domain = domainEntry.key.toString();
      final domainValue = domainEntry.value;
      if (domainValue is! Map) continue;
      for (final serviceEntry in domainValue.entries) {
        services.add(
          HomeAssistantService.fromJson(
            domain,
            serviceEntry.key.toString(),
            serviceEntry.value,
          ),
        );
      }
    }
  }

  return HomeAssistantCatalog(
    entities: entities,
    services: services,
    areas: homeAssistantOptionsFromResponse(areasPayload),
    devices: homeAssistantOptionsFromResponse(devicesPayload),
    floors: homeAssistantOptionsFromResponse(floorsPayload),
    labels: homeAssistantOptionsFromResponse(labelsPayload),
    serverNames: serverId == null
        ? const {}
        : {
            serverId: serverName?.trim().isNotEmpty == true
                ? serverName!
                : serverId,
          },
  );
}

List<HomeAssistantOption> homeAssistantOptionsFromResponse(dynamic payload) {
  if (payload is! List) return const [];
  final result = <HomeAssistantOption>[];
  for (final value in payload) {
    if (value is String && value.trim().isNotEmpty) {
      result.add(HomeAssistantOption(id: value.trim()));
      continue;
    }
    if (value is! Map) continue;
    final id =
        (value['id'] ??
                value['area_id'] ??
                value['device_id'] ??
                value['floor_id'] ??
                value['label_id'] ??
                value['entity_id'])
            ?.toString()
            .trim() ??
        '';
    if (id.isEmpty) continue;
    final label =
        (value['name'] ??
                value['label'] ??
                value['friendly_name'] ??
                value['original_name'])
            ?.toString() ??
        '';
    result.add(HomeAssistantOption(id: id, label: label));
  }
  return result;
}

/// Converts an arbitrary flow value into entity IDs without changing its
/// original shape. This is used only for rendering a selection UI.
List<String> entityIdsFromValue(dynamic value) {
  if (value is String) {
    return value
        .split(RegExp(r'[,\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is List) {
    return value
        .expand<String>((item) {
          if (item is String) return [item];
          if (item is Map) {
            final id = (item['entity_id'] ?? item['entityId'] ?? item['id'])
                ?.toString();
            return id == null || id.isEmpty ? const [] : [id];
          }
          return const [];
        })
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

dynamic entityValueWithShape(dynamic original, List<String> values) {
  if (original is List) return values;
  if (original is String || original == null) return values.join(', ');
  return values.join(', ');
}

String encodeServiceData(dynamic value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ')
        .convert(value ?? <String, dynamic>{});
  } catch (_) {
    return value?.toString() ?? '';
  }
}
