import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class SignalingClient {
  WebSocketChannel? _channel;
  final String myUuid;

  Function(Map<String, dynamic>)? onOfferReceived;
  Function(Map<String, dynamic>)? onAnswerReceived;
  Function(Map<String, dynamic>)? onCandidateReceived;
  Function(Map<String, dynamic>)? onCloseConnection;
  
  SignalingClient({required this.myUuid});

  void connect(String serverUrl){
    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

    send({
      'type': 'login',
      'id': myUuid,
    });

    _channel!.stream.listen((message) {
      _handleIncomingMessage(message);
    }, onError: (error) {
      print("WebSocket error: $error");
    }, onDone: () {
      print("WebSocket closed");
    });

  }

  void _handleIncomingMessage(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];

      switch (type) {
        case 'offer':
          onOfferReceived?.call(data);
          break;
        case 'answer':
          onAnswerReceived?.call(data);
          break;
        case 'candidate':
          onCandidateReceived?.call(data);
          break;
        case 'close':
          onCloseConnection?.call(data);
          break;
        default:
          logger.w("Unknown message type: $type");
      }
    } catch (e) {
      logger.e("Error parsing signaling message: $e");
    }

  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(utf8.encode(jsonEncode(message)));
    }
  }

  void dispose() {
    _channel?.sink.close();
  }
}