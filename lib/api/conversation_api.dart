// lib/api/conversation_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart'; 

/// Mi clase para interactuar con los endpoints /api/conversations del backend.
///
/// Se encarga de obtener la lista de chats, crear nuevos chats
/// y cargar el historial de mensajes de un chat.
class ConversationApi {
  /// URL base de mi backend, tomada de mis constantes.
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la lista de todas las conversaciones en las que participa el usuario actual.
  /// Llama a GET /api/conversations.
  ///
  /// Devuelve una lista de (JSON de ConversationDto), que incluye datos
  /// de los participantes y el último mensaje (si existe).
  Future<List<dynamic>> getConversations(String token) async {
    print("ConversationApi [getConversations]: Solicitando lista de conversaciones...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations'),
        headers: { 'Authorization': 'Bearer $token' },
      );

      print("ConversationApi [getConversations]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final List<dynamic> conversations = jsonDecode(response.body);
        print("ConversationApi [getConversations]: ${conversations.length} conversaciones recibidas.");
        return conversations;
      } else {
        String errorMessage = 'Error desconocido al obtener conversaciones.';
        try { final errorBody = jsonDecode(response.body); errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body; } catch (_) { errorMessage = response.body; }
        print("ConversationApi [getConversations] Error: $errorMessage");
        throw Exception('Error al cargar conversaciones: $errorMessage');
      }
    } catch (e) {
      print("ConversationApi [getConversations] Excepción: $e");
      throw Exception('No se pudo conectar al servidor para obtener conversaciones: ${e.toString()}');
    }
  }

  /// Crea una nueva conversación (generalmente directa 1 a 1).
  /// Llama a POST /api/conversations.
  ///
  /// Mi backend está configurado para que si ya existe una conversación
  /// directa con ese `userId`, simplemente la devuelva en lugar de crear una nueva.
  ///
  /// Devuelve el JSON de la conversación (ConversationDto) creada o encontrada.
  Future<Map<String, dynamic>> createConversation(String token, int userId) async {
     print("ConversationApi [createConversation]: Creando conversación con usuario ID $userId...");
     try {
       final response = await http.post(
         Uri.parse('$_baseUrl/api/conversations'),
         headers: {
           'Authorization': 'Bearer $token',
           'Content-Type': 'application/json',
         },
         // El DTO CreateConversationRequest de mi backend
         body: jsonEncode({
           'type': 'direct', // Por ahora solo creo chats directos
           'participantIds': [userId], // El ID del *otro* usuario
         }),
       );

        print("ConversationApi [createConversation]: Respuesta recibida - Status: ${response.statusCode}");
       if (response.statusCode == 200) {
         final Map<String, dynamic> conversationData = jsonDecode(response.body);
         print("ConversationApi [createConversation]: Conversación creada/obtenida con ID ${conversationData['id']}.");
         return conversationData;
       } else {
          String errorMessage = 'Error desconocido al crear conversación.';
          try { final errorBody = jsonDecode(response.body); errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body; } catch (_) { errorMessage = response.body; }
          print("ConversationApi [createConversation] Error: $errorMessage");
          throw Exception('Error al crear conversación: $errorMessage');
       }
     } catch (e) {
        print("ConversationApi [createConversation] Excepción: $e");
        throw Exception('No se pudo conectar al servidor para crear conversación: ${e.toString()}');
     }
  }

  /// Obtiene el historial de mensajes cifrados para una conversación específica.
  /// Llama a GET /api/conversations/{conversationId}/messages.
  ///
  /// Devuelve una lista de (JSON de MessageHistoryDto), que contiene
  /// el `ciphertext`, `encryptedKey`, `senderId`, etc.
  /// Estos datos *aún no están descifrados*.
  Future<List<dynamic>> getMessages(String token, int conversationId) async {
    print("ConversationApi [getMessages]: Solicitando historial para conversación ID $conversationId...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations/$conversationId/messages'),
        headers: { 'Authorization': 'Bearer $token' },
      );

       print("ConversationApi [getMessages]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final List<dynamic> messages = jsonDecode(response.body);
         print("ConversationApi [getMessages]: ${messages.length} mensajes recibidos del historial.");
        return messages;
      } else {
          String errorMessage = 'Error desconocido al obtener mensajes.';
          try { final errorBody = jsonDecode(response.body); errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body; } catch (_) { errorMessage = response.body; }
           print("ConversationApi [getMessages] Error: $errorMessage");
          throw Exception('Error al cargar historial: $errorMessage');
      }
    } catch (e) {
       print("ConversationApi [getMessages] Excepción: $e");
       throw Exception('No se pudo conectar al servidor para obtener historial: ${e.toString()}');
    }
  }
} 