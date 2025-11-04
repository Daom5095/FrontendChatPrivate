// lib/services/socket_service.dart

import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_constants.dart';
import 'crypto_service.dart'; 
import '../api/messaging_api.dart'; 

/// Mi servicio para manejar la conexión WebSocket (usando STOMP)
/// y el envío/recepción de mensajes en tiempo real.
class SocketService {
  /// El cliente STOMP que maneja la conexión.
  late StompClient _stompClient;
  /// Flag para saber si estamos conectados activamente.
  bool isConnected = false;
  /// Flag para saber si `connect()` fue llamado y el cliente está inicializado.
  bool _isStompClientInitialized = false;

  // --- Dependencias ---
  /// Mi caja de herramientas criptográficas.
  final CryptoService _cryptoService = CryptoService();
  /// Mi cliente API para obtener claves públicas.
  final MessagingApi _messagingApi = MessagingApi();
  /// El token JWT actual, necesario para `sendMessage` (para llamar a MessagingApi).
  String? _currentToken;

  /// Inicia la conexión con el servidor WebSocket.
  ///
  /// 1. Configura el cliente STOMP (URL, headers de autenticación, callbacks).
  /// 2. Se activa (`_stompClient.activate()`).
  /// 3. En el callback `onConnect`, se suscribe a la cola personal
  ///    del usuario (`/user/queue/messages`) para recibir mensajes.
  void connect(String token, Function(StompFrame) onMessageReceived) {
    print("SocketService: Intentando conectar al WebSocket...");
    _currentToken = token; // Guarda el token para usarlo al enviar mensajes

    _stompClient = StompClient(
      config: StompConfig(
        // Construye la URL WebSocket (ws://) desde la baseUrl (http://)
        url: '${AppConstants.baseUrl.replaceFirst('http', 'ws')}/ws', // Endpoint WebSocket de mi backend
        
        /// Callback cuando la conexión STOMP es exitosa.
        onConnect: (StompFrame frame) {
          isConnected = true; // Marcar como conectado
          print("SocketService: Conectado exitosamente al WebSocket.");
          
          // Una vez conectados, nos suscribimos a nuestra cola personal.
          // El backend (Spring) mapea '/user/queue/messages' a la
          // cola específica de este usuario autenticado.
          _stompClient.subscribe(
            destination: '/user/queue/messages', // Destino estándar para mensajes privados
            callback: onMessageReceived, // La función (en ChatScreen) que manejará los mensajes
          );
           print("SocketService: Suscrito a /user/queue/messages.");
        },
        
        /// Callback para errores de WebSocket (ej. no se puede conectar).
        onWebSocketError: (dynamic error) {
          print("SocketService ERROR de WebSocket: ${error.toString()}");
          isConnected = false; // Marcar como desconectado
        },
        
        /// Callback para errores STOMP (ej. autenticación fallida).
        onStompError: (StompFrame frame) {
           print("SocketService ERROR STOMP: ${frame.headers} - ${frame.body}");
           isConnected = false;
        },
        
        // Pasamos el token JWT en las cabeceras para la autenticación
        // tanto en la conexión WebSocket inicial como en el frame CONNECT de STOMP.
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        
        // Tiempos de espera y heartbeats (para mantener viva la conexión)
        connectionTimeout: const Duration(seconds: 15),
        heartbeatOutgoing: const Duration(seconds: 20), // Enviar pings
        heartbeatIncoming: const Duration(seconds: 20), // Esperar pongs
      ),
    );

    _isStompClientInitialized = true; // Marcar que el cliente existe
    _stompClient.activate(); // Iniciar la conexión
  }

  /// **Envía un mensaje cifrado End-to-End.**
  ///
  /// Este es el flujo E2EE para un mensaje nuevo:
  ///
  /// 1. **Generar Clave Simétrica:**
  ///    - Crea una clave AES-CBC y un IV únicos para *este* mensaje (`_cryptoService.generateAESKeyAndIV_CBC`).
  /// 2. **Cifrar Mensaje:**
  ///    - Cifra el `plainTextMessage` usando esta clave AES (`_cryptoService.encryptAES_CBC`).
  /// 3. **Combinar Clave/IV:**
  ///    - Junta la clave AES (Base64) y el IV (Base64) en un solo string: "clave:iv" (`_cryptoService.combineKeyIV`).
  /// 4. **Cifrado Asimétrico (para cada destinatario):**
  ///    - Itera sobre la lista de `participantIds` (que debe incluirme a mí).
  ///    - Para cada `userId`:
  ///      a. Llama a `_messagingApi.getPublicKey` para obtener la clave pública RSA de ese usuario.
  ///      b. Cifra el string "clave:iv" usando esa clave pública (`_cryptoService.encryptRSA`).
  ///      c. Almacena el resultado en un mapa: `encryptedKeysMap[userId] = claveCifrada`.
  /// 5. **Enviar Payload:**
  ///    - Envía un mensaje STOMP a `/app/chat.send` (el controlador de mi backend)
  ///      con un JSON (StompMessagePayload) que contiene:
  ///      - `conversationId`
  ///      - `ciphertext` (el mensaje cifrado con AES)
  ///      - `encryptedKeys` (el mapa de claves AES cifradas con RSA)
  Future<void> sendMessage(int conversationId, String plainTextMessage, List<int> participantIds) async {
    // Validar estado antes de enviar
    if (!isConnected || !_isStompClientInitialized || _currentToken == null) {
      print("SocketService [sendMessage] Error: No conectado, no inicializado o token nulo. No se puede enviar.");
      throw Exception("No conectado al servidor para enviar mensaje.");
    }

    print("SocketService [sendMessage]: Iniciando proceso de envío E2EE para conv $conversationId...");

    try {
      // 1. Generar nueva clave AES + IV para ESTE mensaje (usando CBC)
      final aesKeyMap = _cryptoService.generateAESKeyAndIV_CBC();
      final base64AesKey = aesKeyMap['key']!;
      final base64AesIV = aesKeyMap['iv']!;
      print("SocketService [sendMessage]: Clave/IV AES-CBC generados.");

      // 2. Cifrar el mensaje de texto plano con AES-CBC
      final ciphertext = _cryptoService.encryptAES_CBC(plainTextMessage, base64AesKey, base64AesIV);
      print("SocketService [sendMessage]: Mensaje cifrado con AES-CBC.");

      // 3. Combinar clave AES y IV en un solo string (para cifrar con RSA)
      final combinedKeyIV = _cryptoService.combineKeyIV(base64AesKey, base64AesIV);
      print("SocketService [sendMessage]: Clave/IV combinados.");

      // 4. Cifrar la clave AES+IV combinada para cada participante
      final Map<String, String> encryptedKeysMap = {}; // Mapa { "userId": "claveAEScifradaConRSA" }
      print("SocketService [sendMessage]: Obteniendo claves públicas y cifrando clave AES para ${participantIds.length} participantes...");
      
      for (var userId in participantIds) {
        try {
          // 4a. Obtener clave pública RSA del destinatario desde la API
          print("SocketService [sendMessage]: Obteniendo clave pública para usuario $userId...");
          final publicKeyPem = await _messagingApi.getPublicKey(_currentToken!, userId);
          
          // 4b. Cifrar la clave AES+IV combinada usando esa clave pública
          final encryptedCombinedKey = await _cryptoService.encryptRSA(combinedKeyIV, publicKeyPem);
          
          // 4c. Guardar en el mapa, usando el ID del usuario como clave (en formato String)
          encryptedKeysMap[userId.toString()] = encryptedCombinedKey;
           print("SocketService [sendMessage]: Clave AES cifrada para usuario $userId.");
        } catch (e) {
          // Si falla para un usuario, lo registro pero continúo con los demás
          // (ej. si un usuario fue eliminado pero sigue en la lista de participantes).
          print("SocketService [sendMessage] WARNING: Error al obtener/cifrar clave para usuario $userId: $e. Omitiendo destinatario.");
        }
      } // Fin del bucle for

       // Validación crítica: ¿Pudimos cifrar para alguien?
       if (encryptedKeysMap.isEmpty) {
         print("SocketService [sendMessage] ERROR CRÍTICO: No se pudo cifrar la clave AES para NINGÚN destinatario. Abortando envío.");
         throw Exception("No se pudo cifrar la clave para ningún destinatario.");
       }
       print("SocketService [sendMessage]: Clave AES cifrada para ${encryptedKeysMap.length} destinatarios.");

      // 5. Enviar el payload completo al backend vía STOMP
      print("SocketService [sendMessage]: Enviando payload STOMP a /app/chat.send...");
      _stompClient.send(
        destination: '/app/chat.send', // Endpoint STOMP del backend (MessageController)
        // El cuerpo es un JSON con los datos que espera StompMessagePayload en el backend
        body: json.encode({
          'conversationId': conversationId, // ID de la conversación
          'ciphertext': ciphertext, // Mensaje cifrado con AES
          'encryptedKeys': encryptedKeysMap, // Mapa de claves AES cifradas con RSA
        }),
      );
      print('SocketService [sendMessage]: Mensaje enviado (STOMP send llamado).');

    } catch (e) {
      // Capturar cualquier error durante el proceso de cifrado o envío
      print("SocketService [sendMessage] ERROR general: $e");
      // Re-lanzar la excepción para que la UI (ChatScreen) pueda reaccionar
      rethrow;
    }
  }

  /// Desconecta el cliente STOMP del servidor WebSocket.
  ///
  /// Se llama cuando el usuario cierra sesión o al cerrar la pantalla de chat.
  void disconnect() {
    print("SocketService: Solicitando desconexión...");
    // Verificar si el cliente fue inicializado y está activo antes de desactivar
    if (_isStompClientInitialized && _stompClient.isActive) {
      _stompClient.deactivate(); // Envía el comando DISCONNECT y cierra la conexión
      print("SocketService: Cliente STOMP desactivado.");
    } else if (!_isStompClientInitialized) {
       print("SocketService: Intento de desconectar pero el cliente no fue inicializado.");
    } else {
       print("SocketService: Cliente STOMP ya estaba inactivo.");
    }
    
    // Actualizar estado local independientemente
    isConnected = false;
    _currentToken = null; // Limpiar token
    _isStompClientInitialized = false; // Marcar como no inicializado
    print("SocketService: Desconectado lógicamente.");
  }
} 