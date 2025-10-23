// lib/services/socket_service.dart

import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_constants.dart';
import 'crypto_service.dart';
import '../api/messaging_api.dart';
// Quitamos AuthService si no se usa directamente aquí

class SocketService {
  late StompClient _stompClient;
  bool isConnected = false;
  // Flag para saber si _stompClient ha sido inicializado por connect()
  bool _isStompClientInitialized = false;

  final CryptoService _cryptoService = CryptoService();
  final MessagingApi _messagingApi = MessagingApi();
  String? _currentToken;

  void connect(String token, Function(StompFrame) onMessageReceived) {
    _currentToken = token;
    _stompClient = StompClient( // Aquí se inicializa
      config: StompConfig(
        url: '${AppConstants.baseUrl.replaceFirst('http', 'ws')}/ws',
        onConnect: (StompFrame frame) {
          isConnected = true;
          print("Conectado al WebSocket");
          _stompClient.subscribe(
            destination: '/user/queue/messages',
            callback: onMessageReceived,
          );
        },
        onWebSocketError: (dynamic error) {
          print("Error de WebSocket: ${error.toString()}");
          isConnected = false;
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        connectionTimeout: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 20000),
        heartbeatIncoming: const Duration(seconds: 20000),
      ),
    );
    _isStompClientInitialized = true; // Marcamos como inicializado
    _stompClient.activate();
  }

  Future<void> sendMessage(int conversationId, String plainTextMessage, List<int> participantIds) async {
    // ... (El método sendMessage no cambia, permanece igual que en la corrección anterior) ...
    if (!isConnected || _currentToken == null) {
      print("No conectado al socket o token no disponible, no se puede enviar mensaje.");
      return;
    }
    try {
      final aesKeyMap = _cryptoService.generateAESKeyAndIV();
      final base64AesKey = aesKeyMap['key']!;
      final base64AesIV = aesKeyMap['iv']!;
      final ciphertext = _cryptoService.encryptAES(plainTextMessage, base64AesKey, base64AesIV);
      final combinedKeyIV = _cryptoService.combineKeyIV(base64AesKey, base64AesIV);
      final Map<String, String> encryptedKeysMap = {};
      for (var userId in participantIds) {
        try {
          final publicKeyPem = await _messagingApi.getPublicKey(_currentToken!, userId);
          final encryptedCombinedKey = await _cryptoService.encryptRSA(combinedKeyIV, publicKeyPem);
          encryptedKeysMap[userId.toString()] = encryptedCombinedKey;
        } catch (e) {
          print("Error al obtener/cifrar clave para usuario $userId: $e. Omitiendo.");
        }
      }
       if (encryptedKeysMap.isEmpty) {
         print("Error crítico: No se pudo cifrar la clave AES para ningún destinatario.");
         throw Exception("No se pudo cifrar la clave para ningún destinatario.");
       }
      _stompClient.send(
        destination: '/app/chat.send',
        body: json.encode({
          'conversationId': conversationId,
          'ciphertext': ciphertext,
          'encryptedKeys': encryptedKeysMap,
        }),
      );
      print('Mensaje CIFRADO enviado a conv $conversationId para usuarios: $participantIds');
    } catch (e) {
      print("Error general al cifrar o enviar mensaje: $e");
      rethrow;
    }
  }

  // --- MÉTODO DISCONNECT CORREGIDO ---
  void disconnect() {
    // Verificamos si el cliente fue inicializado Y si está activo antes de desactivar
    if (_isStompClientInitialized && _stompClient.isActive) {
      _stompClient.deactivate();
      print("STOMP client desactivado.");
    } else {
       print("STOMP client no estaba activo o inicializado, no se necesita desactivar.");
    }
    isConnected = false;
    _currentToken = null;
    _isStompClientInitialized = false; // Resetear al desconectar
    print("Desconectado lógicamente del WebSocket");
  }
} // Fin de la clase SocketService