import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectNodeRedSocket(Uri uri, Map<String, String> headers) =>
    HtmlWebSocketChannel.connect(uri.toString());
