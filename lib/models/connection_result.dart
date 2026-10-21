import 'flow_bundle.dart';
import 'node_red_connection.dart';

class ConnectionResult {
  const ConnectionResult(this.connection, this.bundle);

  final NodeRedConnection connection;
  final FlowBundle bundle;
}
