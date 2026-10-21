enum NodeRedAuthMode { none, credentials, bearer, gateway }

class NodeRedConnection {
  const NodeRedConnection({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.authMode,
    this.username = '',
    this.password = '',
    this.bearerToken = '',
    this.gatewayUrl = '',
    this.gatewayDeviceId = '',
    this.gatewayRole = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final NodeRedAuthMode authMode;
  final String username;
  final String password;
  final String bearerToken;
  final String gatewayUrl;
  final String gatewayDeviceId;
  final String gatewayRole;

  bool get isGateway => authMode == NodeRedAuthMode.gateway;

  NodeRedConnection copyWith({
    String? id,
    String? name,
    String? baseUrl,
    NodeRedAuthMode? authMode,
    String? username,
    String? password,
    String? bearerToken,
    String? gatewayUrl,
    String? gatewayDeviceId,
    String? gatewayRole,
  }) => NodeRedConnection(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    authMode: authMode ?? this.authMode,
    username: username ?? this.username,
    password: password ?? this.password,
    bearerToken: bearerToken ?? this.bearerToken,
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    gatewayDeviceId: gatewayDeviceId ?? this.gatewayDeviceId,
    gatewayRole: gatewayRole ?? this.gatewayRole,
  );

  Map<String, Object?> toJson({bool includeSecrets = true}) => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'authMode': authMode.name,
    if (includeSecrets) 'username': username,
    if (includeSecrets) 'password': password,
    if (includeSecrets) 'bearerToken': bearerToken,
    'gatewayUrl': gatewayUrl,
    'gatewayDeviceId': gatewayDeviceId,
    'gatewayRole': gatewayRole,
  };

  factory NodeRedConnection.fromJson(Map<String, dynamic> json) =>
      NodeRedConnection(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        authMode: NodeRedAuthMode.values.firstWhere(
          (mode) => mode.name == json['authMode'],
          orElse: () => NodeRedAuthMode.none,
        ),
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        bearerToken: json['bearerToken'] as String? ?? '',
        gatewayUrl: json['gatewayUrl'] as String? ?? '',
        gatewayDeviceId: json['gatewayDeviceId'] as String? ?? '',
        gatewayRole: json['gatewayRole'] as String? ?? '',
      );
}
