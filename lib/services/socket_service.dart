// lib/services/socket_service.dart

import 'dart:async'; 
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_constants.dart';
import 'crypto_service.dart';
import '../api/messaging_api.dart';

/// Mi servicio para manejar la conexión WebSocket (usando STOMP)
/// y el envío/recepción de mensajes en tiempo real.
///
/// Convertido a un Singleton para mantener una única conexión
/// persistente mientras la app esté logueada.
class SocketService {
 
  static final SocketService _instance = SocketService._internal();

  /// Constructor privado interno
  SocketService._internal();

  /// El punto de acceso global a la única instancia de este servicio
  static SocketService get instance => _instance;
  
  late StompClient _stompClient;
  bool isConnected = false;
  bool _isStompClientInitialized = false;

  // --- Stream para transmitir mensajes entrantes ---
  /// Un Stream "broadcast" permite que múltiples pantallas (HomeScreen, ChatScreen)
  /// escuchen los mensajes entrantes a la vez.
  final _messageStreamController = StreamController<StompFrame>.broadcast();

  /// Las pantallas escucharán este Stream para recibir mensajes.
  Stream<StompFrame> get messages => _messageStreamController.stream;
  // --- Fin: Stream ---

  final CryptoService _cryptoService = CryptoService();
  final MessagingApi _messagingApi = MessagingApi();
  String? _currentToken;

  /// Inicia la conexión con el servidor WebSocket.
  ///
  /// Ya NO recibe un callback, en su lugar, alimentará el Stream `messages`.
  void connect(String token) {
    // Evitar reconexiones si ya está conectado o inicializado
    if (_isStompClientInitialized && _stompClient.isActive) {
      print("SocketService: Ya está conectado.");
      return;
    }

    print("SocketService: Intentando conectar al WebSocket...");
    _currentToken = token; // Guarda el token para usarlo al enviar mensajes

    _stompClient = StompClient(
      config: StompConfig(
        url: '${AppConstants.baseUrl.replaceFirst('http', 'ws')}/ws',
        onConnect: (StompFrame frame) {
          isConnected = true;
          print("SocketService: Conectado exitosamente al WebSocket.");

          // 1. Suscribirse a la cola personal de MENSAJES.
          _stompClient.subscribe(
            destination: '/user/queue/messages',
            callback: (StompFrame frame) {
              // Añade el mensaje al stream para que los listeners (pantallas) reaccionen
              _messageStreamController.add(frame);
            },
          );
          print("SocketService: Suscrito a /user/queue/messages.");

    
          // 2. Suscribirse a la cola personal de ERRORES.
          _stompClient.subscribe(
            destination: '/user/queue/errors',
            callback: (StompFrame frame) {
              print("SocketService [ERROR STOMP]: Error de WebSocket recibido:");
              if (frame.body != null) {
                try {
                  final errorBody = json.decode(frame.body!);
                  print(
                      "SocketService [ERROR STOMP]: Tipo: ${errorBody['type']}, Mensaje: ${errorBody['message']}");
                  // Aquí podrías mostrar un Toast/Snackbar global al usuario
                  // ej: ToastService.showError("Error: ${errorBody['message']}");
                } catch (e) {
                  print(
                      "SocketService [ERROR STOMP]: Cuerpo no JSON: ${frame.body}");
                }
              } else {
                print(
                    "SocketService [ERROR STOMP]: Error recibido sin cuerpo.");
              }
            },
          );
          print("SocketService: Suscrito a /user/queue/errors.");
        },
        onWebSocketError: (dynamic error) {
          print("SocketService ERROR de WebSocket: ${error.toString()}");
          isConnected = false;
          _isStompClientInitialized = false; // Permitir reconexión
        },
        onStompError: (StompFrame frame) {
          print("SocketService ERROR STOMP: ${frame.headers} - ${frame.body}");
          isConnected = false;
          _isStompClientInitialized = false; // Permitir reconexión
        },
        onDisconnect: (frame) {
          print("SocketService: Desconectado.");
          isConnected = false;
          _isStompClientInitialized = false; // Permitir reconexión
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        connectionTimeout: const Duration(seconds: 15),
        heartbeatOutgoing: const Duration(seconds: 20),
        heartbeatIncoming: const Duration(seconds: 20),
      ),
    );

    _isStompClientInitialized = true;
    _stompClient.activate();
  }

  /// Envía un mensaje cifrado End-to-End.
  ///
  /// La lógica interna no cambia, pero ahora usa la instancia singleton.
  Future<void> sendMessage(int conversationId, String plainTextMessage,
      List<int> participantIds) async {
    if (!isConnected || !_isStompClientInitialized || _currentToken == null) {
      print(
          "SocketService [sendMessage] Error: No conectado, no inicializado o token nulo. No se puede enviar.");
      throw Exception("No conectado al servidor para enviar mensaje.");
    }

    print(
        "SocketService [sendMessage]: Iniciando proceso de envío E2EE para conv $conversationId...");

    try {
      // 1. Generar nueva clave AES + IV
      final aesKeyMap = _cryptoService.generateAESKeyAndIV_CBC();
      final base64AesKey = aesKeyMap['key']!;
      final base64AesIV = aesKeyMap['iv']!;
      print("SocketService [sendMessage]: Clave/IV AES-CBC generados.");

      // 2. Cifrar el mensaje de texto plano con AES-CBC
      final ciphertext =
          _cryptoService.encryptAES_CBC(plainTextMessage, base64AesKey, base64AesIV);
      print("SocketService [sendMessage]: Mensaje cifrado con AES-CBC.");

      // 3. Combinar clave AES y IV
      final combinedKeyIV =
          _cryptoService.combineKeyIV(base64AesKey, base64AesIV);
      print("SocketService [sendMessage]: Clave/IV combinados.");

      // 4. Cifrar la clave AES+IV combinada para cada participante
      final Map<String, String> encryptedKeysMap = {};
      print(
          "SocketService [sendMessage]: Obteniendo claves públicas y cifrando clave AES para ${participantIds.length} participantes...");

      for (var userId in participantIds) {
        try {
          // 4a. Obtener clave pública RSA del destinatario
          print(
              "SocketService [sendMessage]: Obteniendo clave pública para usuario $userId...");
          final publicKeyPem =
              await _messagingApi.getPublicKey(_currentToken!, userId);

          // 4b. Cifrar la clave AES+IV combinada
          final encryptedCombinedKey =
              await _cryptoService.encryptRSA(combinedKeyIV, publicKeyPem);

          // 4c. Guardar en el mapa
          encryptedKeysMap[userId.toString()] = encryptedCombinedKey;
          print(
              "SocketService [sendMessage]: Clave AES cifrada para usuario $userId.");
        } catch (e) {
          print(
              "SocketService [sendMessage] WARNING: Error al obtener/cifrar clave para usuario $userId: $e. Omitiendo destinatario.");
        }
      }

      if (encryptedKeysMap.isEmpty) {
        print(
            "SocketService [sendMessage] ERROR CRÍTICO: No se pudo cifrar la clave AES para NINGÚN destinatario. Abortando envío.");
        throw Exception("No se pudo cifrar la clave para ningún destinatario.");
      }
      print(
          "SocketService [sendMessage]: Clave AES cifrada para ${encryptedKeysMap.length} destinatarios.");

      // 5. Enviar el payload completo al backend vía STOMP
      print("SocketService [sendMessage]: Enviando payload STOMP a /app/chat.send...");
      _stompClient.send(
        destination: '/app/chat.send',
        body: json.encode({
          'conversationId': conversationId,
          'ciphertext': ciphertext,
          'encryptedKeys': encryptedKeysMap,
        }),
      );
      print('SocketService [sendMessage]: Mensaje enviado (STOMP send llamado).');
    } catch (e) {
      print("SocketService [sendMessage] ERROR general: $e");
      rethrow;
    }
  }

  /// Desconecta el cliente STOMP del servidor WebSocket.
  void disconnect() {
    print("SocketService: Solicitando desconexión...");
    if (_isStompClientInitialized && _stompClient.isActive) {
      _stompClient.deactivate();
      print("SocketService: Cliente STOMP desactivado.");
    } else if (!_isStompClientInitialized) {
      print(
          "SocketService: Intento de desconectar pero el cliente no fue inicializado.");
    } else {
      print("SocketService: Cliente STOMP ya estaba inactivo.");
    }

    isConnected = false;
    _currentToken = null;
    _isStompClientInitialized = false;
    print("SocketService: Desconectado lógicamente.");
  }
}