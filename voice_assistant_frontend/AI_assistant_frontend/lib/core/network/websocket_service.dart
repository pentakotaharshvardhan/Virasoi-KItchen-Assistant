import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Generic reconnecting WebSocket wrapper used by:
///  - the Ingredient screen (server pushes "item confirmed" events while
///    the user talks to the assistant so the grid updates live)
///  - the Voice Assistant screen (bi-directional STT text / assistant
///    reply / TTS-ready events)
///
/// Usage:
///   final ws = AppWebSocketService(url: ApiConstants.wsVoiceAssistant(id));
///   ws.connect();
///   ws.messages.listen((json) { ... });
///   ws.send({'type': 'user_text', 'text': 'I have two onions'});
class AppWebSocketService {
  AppWebSocketService({required this.url, this.token});

  final String url;
  final String? token;
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  Timer? _reconnectTimer;
  bool _manuallyClosed = false;

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  Stream<bool> get connectionState => _connectionController.stream;

  void connect() {
    _manuallyClosed = false;

    try {
      Uri uri = Uri.parse(url);

      // Force secure WebSocket
      uri = uri.replace(scheme: 'wss');

      // Attach token as query param
      if (token != null) {
        uri = uri.replace(queryParameters: {
          ...uri.queryParameters,
          'token': token!,
        });
      }

      print("WS: Connecting to $uri");

      _channel = IOWebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (event) {
          print("WS Message: $event");
          try {
            final decoded = jsonDecode(event.toString()) as Map<String, dynamic>;
            _controller.add(decoded);
          } catch (e) {
            print("WS Decode error: $e");
          }
        },
        onError: (e) {
          print("WS Error: $e");
          _connectionController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          print("WS Closed");
          _connectionController.add(false);
          if (!_manuallyClosed) _scheduleReconnect();
        },
      );
      _connectionController.add(true);
    } catch (e) {
      print("WS Setup error: $e");
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_manuallyClosed) connect();
    });
  }

  void send(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      _channel?.sink.add(jsonEncode(payload));
    } else {
      // Direct binary support for raw audio bytes
      _channel?.sink.add(payload);
    }
  }

  void close() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }

  void dispose() {
    close();
    _controller.close();
    _connectionController.close();
  }
}
