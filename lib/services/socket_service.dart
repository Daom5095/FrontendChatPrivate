

import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';

class SocketService {
  late StompClient _stompClient;
  bool isConnected = false;

  void connect(String token, Function(StompFrame) onMessageReceived) {
    _stompClient = StompClient(
      config: StompConfig(
        // URL de tu WebSocket
        url: 'ws://localhost:8080/ws',
        onConnect: (StompFrame frame) {
          isConnected = true;
          print("Conectado al WebSocket");

          // Nos suscribimos a la cola personal de mensajes del usuario
          _stompClient.subscribe(
            destination: '/user/queue/messages',
            callback: onMessageReceived,
          );
        },
        onWebSocketError: (dynamic error) => print(error.toString()),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
      ),
    );
    _stompClient.activate();
  }

  void sendMessage(int conversationId, String messageText) {
    if (!isConnected) return;

    // Por ahora enviamos el texto plano. En el siguiente paso lo cifraremos.
    _stompClient.send(
      destination: '/app/chat.send',
      body: json.encode({
        'conversationId': conversationId,
        'ciphertext': messageText,
        // TODO: En el siguiente paso, añadiremos las claves cifradas
        'encryptedKeys': {},
      }),
    );
  }

  void disconnect() {
    _stompClient.deactivate();
    isConnected = false;
    print("Desconectado del WebSocket");
  }
}