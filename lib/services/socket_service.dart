// lib/services/socket_service.dart

import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

class SocketService {
  late StompClient _stompClient;
  bool isConnected = false;

  void connect(String token, Function(StompFrame) onMessageReceived) {
    _stompClient = StompClient(
      config: StompConfig(
        // Asegúrate que la URL base sea correcta
        url: '${AppConstants.baseUrl.replaceFirst('http', 'ws')}/ws',
        onConnect: (StompFrame frame) {
          isConnected = true;
          print("Conectado al WebSocket");

          _stompClient.subscribe(
            destination: '/user/queue/messages', // Suscribe a la cola personal
            callback: onMessageReceived,
          );
        },
        onWebSocketError: (dynamic error) {
             print("Error de WebSocket: ${error.toString()}");
             isConnected = false; // Marcar como desconectado en caso de error
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        // Añadir reintentos de conexión por si acaso
        connectionTimeout: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 20000),
        heartbeatIncoming: const Duration(seconds: 20000),
      ),
    );
    _stompClient.activate();
  }

  // --- MÉTODO CORREGIDO ---
  // Ahora requiere la lista de IDs de los participantes
  void sendMessage(int conversationId, String messageText, List<int> participantIds) {
    if (!isConnected) {
        print("No conectado al socket, no se puede enviar mensaje.");
        return;
    }

    // Creamos el mapa `encryptedKeys`. El backend (`MessageService`)
    // iterará sobre las *claves* de este mapa para saber a quién reenviar el mensaje.
    final Map<String, String> encryptedKeysMap = {
      for (var id in participantIds) id.toString(): 'placeholder_key' // El backend usa las claves (IDs)
    };

    _stompClient.send(
      destination: '/app/chat.send', // Endpoint del backend para recibir mensajes
      body: json.encode({
        'conversationId': conversationId,
        'ciphertext': messageText, // Por ahora, texto plano
        'encryptedKeys': encryptedKeysMap, // Mapa con { "userId": "placeholder_key", ... }
      }),
    );
    print('Mensaje enviado a conv $conversationId para usuarios: $participantIds');
  }

  void disconnect() {
    // Verifica si el cliente está activado antes de intentar desactivar
    if (_stompClient.isActive) {
        _stompClient.deactivate();
    }
    isConnected = false;
    print("Desconectado del WebSocket");
  }
}