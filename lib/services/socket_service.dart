// lib/services/socket_service.dart

import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:convert';
import '../config/app_constants.dart';
import 'crypto_service.dart'; // Importa CryptoService
import '../api/messaging_api.dart'; // Importa MessagingApi

/// Mi servicio para manejar la conexión WebSocket (STOMP) y el envío/recepción de mensajes.
class SocketService {
  late StompClient _stompClient; // El cliente STOMP
  bool isConnected = false; // Flag para saber si estamos conectados activamente
  bool _isStompClientInitialized = false; // Flag para saber si connect() fue llamado

  // Instancias de los servicios que necesito
  final CryptoService _cryptoService = CryptoService();
  final MessagingApi _messagingApi = MessagingApi();
  String? _currentToken; // El token JWT actual para autenticar llamadas

  /// Inicia la conexión con el servidor WebSocket.
  /// Se suscribe a la cola personal del usuario al conectar.
  void connect(String token, Function(StompFrame) onMessageReceived) {
    print("SocketService: Intentando conectar al WebSocket...");
    _currentToken = token; // Guarda el token para usarlo en sendMessage

    // Configuración del cliente STOMP
    _stompClient = StompClient(
      config: StompConfig(
        // Construye la URL WebSocket (ws:// o wss://) desde la baseUrl http
        url: '${AppConstants.baseUrl.replaceFirst('http', 'ws')}/ws', // Endpoint del backend
        onConnect: (StompFrame frame) {
          isConnected = true; // Marcar como conectado
          print("SocketService: Conectado exitosamente al WebSocket.");
          // Una vez conectados, nos suscribimos a nuestra cola personal
          // El backend mapea '/user/queue/messages' a la cola específica de este usuario.
          _stompClient.subscribe(
            destination: '/user/queue/messages', // Destino estándar para mensajes privados
            callback: onMessageReceived, // La función que manejará los mensajes entrantes (en ChatScreen)
          );
           print("SocketService: Suscrito a /user/queue/messages.");
        },
        onWebSocketError: (dynamic error) {
          // Manejar errores de conexión WebSocket
          print("SocketService ERROR de WebSocket: ${error.toString()}");
          isConnected = false; // Marcar como desconectado
          // Aquí podríamos intentar reconectar o notificar al usuario
        },
        onStompError: (StompFrame frame) {
          // Manejar errores a nivel del protocolo STOMP (ej. autenticación fallida)
           print("SocketService ERROR STOMP: ${frame.headers} - ${frame.body}");
           isConnected = false;
        },
        // Pasar el token JWT en las cabeceras para la autenticación
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        // Tiempos de espera y heartbeats (ajustar según necesidad)
        connectionTimeout: const Duration(seconds: 15), // Aumentado un poco
        heartbeatOutgoing: const Duration(seconds: 20), // Enviar heartbeats
        heartbeatIncoming: const Duration(seconds: 20), // Esperar heartbeats
      ),
    );

    _isStompClientInitialized = true; // Marcar que el cliente existe
    _stompClient.activate(); // Iniciar la conexión
  }

  /// **Envía un mensaje cifrado E2EE.**
  /// 1. Genera clave/IV AES-CBC.
  /// 2. Cifra el mensaje con AES-CBC.
  /// 3. Combina clave/IV.
  /// 4. Obtiene clave pública RSA de cada destinatario.
  /// 5. Cifra la clave/IV combinada con cada clave pública RSA.
  /// 6. Envía todo al backend vía STOMP.
  Future<void> sendMessage(int conversationId, String plainTextMessage, List<int> participantIds) async {
    // Validar estado antes de enviar
    if (!isConnected || !_isStompClientInitialized || _currentToken == null) {
      print("SocketService [sendMessage] Error: No conectado, no inicializado o token nulo. No se puede enviar.");
      // Podríamos lanzar una excepción o devolver un bool para indicar fallo
      throw Exception("No conectado al servidor para enviar mensaje.");
    }

    print("SocketService [sendMessage]: Iniciando proceso de envío E2EE para conv $conversationId...");

    try {
      // 1. Generar nueva clave AES + IV para ESTE mensaje (usando CBC)
      // --- ACTUALIZADO al método renombrado ---
      final aesKeyMap = _cryptoService.generateAESKeyAndIV_CBC();
      final base64AesKey = aesKeyMap['key']!;
      final base64AesIV = aesKeyMap['iv']!;
      print("SocketService [sendMessage]: Clave/IV AES-CBC generados.");

      // 2. Cifrar el mensaje de texto plano con AES-CBC
      // --- ACTUALIZADO al método renombrado ---
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
          // Obtener clave pública RSA del destinatario desde la API
          print("SocketService [sendMessage]: Obteniendo clave pública para usuario $userId...");
          final publicKeyPem = await _messagingApi.getPublicKey(_currentToken!, userId);
          // Cifrar la clave AES+IV combinada usando esa clave pública
          final encryptedCombinedKey = await _cryptoService.encryptRSA(combinedKeyIV, publicKeyPem);
          // Guardar en el mapa, usando el ID del usuario como clave (en formato String)
          encryptedKeysMap[userId.toString()] = encryptedCombinedKey;
           print("SocketService [sendMessage]: Clave AES cifrada para usuario $userId.");
        } catch (e) {
          // Si falla para un usuario, lo registramos pero continuamos con los demás
          print("SocketService [sendMessage] WARNING: Error al obtener/cifrar clave para usuario $userId: $e. Omitiendo destinatario.");
          // Podríamos querer notificar al usuario remitente sobre esto.
        }
      } // Fin del bucle for

       // Validación crítica: ¿Pudimos cifrar para alguien?
       if (encryptedKeysMap.isEmpty) {
         print("SocketService [sendMessage] ERROR CRÍTICO: No se pudo cifrar la clave AES para NINGÚN destinatario. Abortando envío.");
         // Lanzar excepción para que ChatScreen pueda manejarlo (ej. quitar el mensaje local)
         throw Exception("No se pudo cifrar la clave para ningún destinatario.");
       }
       print("SocketService [sendMessage]: Clave AES cifrada para ${encryptedKeysMap.length} destinatarios.");

      // 5. Enviar el payload completo al backend vía STOMP
      print("SocketService [sendMessage]: Enviando payload STOMP a /app/chat.send...");
      _stompClient.send(
        destination: '/app/chat.send', // Endpoint STOMP del backend
        // El cuerpo es un JSON con los datos que espera StompMessagePayload en el backend
        body: json.encode({
          'conversationId': conversationId, // ID de la conversación
          'ciphertext': ciphertext, // Mensaje cifrado con AES
          'encryptedKeys': encryptedKeysMap, // Mapa de claves AES cifradas con RSA
        }),
        // Podríamos añadir cabeceras STOMP aquí si fueran necesarias
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
  void disconnect() {
    print("SocketService: Solicitando desconexión...");
    // Verificar si el cliente fue inicializado y está activo antes de desactivar
    // para evitar errores si se llama a disconnect múltiples veces o antes de connect.
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
    _currentToken = null; // Limpiar token al desconectar
    _isStompClientInitialized = false; // Marcar como no inicializado
    print("SocketService: Desconectado lógicamente.");
  }
} // Fin de la clase SocketService