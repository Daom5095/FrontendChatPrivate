// lib/api/conversation_api.dart

import 'dart:convert';
import 'package/http/http.dart' as http;
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

/// Mi clase para interactuar con los endpoints /api/conversations del backend.
class ConversationApi {
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la lista de todas las conversaciones en las que participa el usuario actual.
  Future<List<dynamic>> getConversations(String token) async {
    print("ConversationApi [getConversations]: Solicitando lista...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations'),
        headers: {'Authorization': 'Bearer $token'},
      );
      print("ConversationApi [getConversations]: Respuesta - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final List<dynamic> conversations = jsonDecode(response.body);
        print("ConversationApi [getConversations]: ${conversations.length} recibidas.");
        return conversations;
      } else {
        // Error de API
        String errorMessage = 'Error desconocido.';
        try {
           final errorBody = jsonDecode(response.body);
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) { errorMessage = response.body; }
        print("ConversationApi [getConversations] Error API: $errorMessage");
        throw Exception('Error al cargar conversaciones: $errorMessage');
      }
    } catch (e) {
      // Error de red/inesperado
      print("ConversationApi [getConversations] Excepción: $e"); // Log añadido
      throw Exception('No se pudo conectar al servidor (conversaciones): ${e.toString()}');
    }
  }

  /// Crea una nueva conversación (generalmente directa 1 a 1).
  Future<Map<String, dynamic>> createConversation(String token, int userId) async {
     print("ConversationApi [createConversation]: Creando con usuario ID $userId...");
     try {
       final response = await http.post(
         Uri.parse('$_baseUrl/api/conversations'),
         headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
         body: jsonEncode({'type': 'direct', 'participantIds': [userId]}),
       );
       print("ConversationApi [createConversation]: Respuesta - Status: ${response.statusCode}");
       if (response.statusCode == 200) {
         final Map<String, dynamic> conversationData = jsonDecode(response.body);
         print("ConversationApi [createConversation]: Creada/Obtenida ID ${conversationData['id']}.");
         return conversationData;
       } else {
          // Error de API
          String errorMessage = 'Error desconocido.';
          try {
             final errorBody = jsonDecode(response.body);
             errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
          } catch (_) { errorMessage = response.body; }
          print("ConversationApi [createConversation] Error API: $errorMessage");
          throw Exception('Error al crear conversación: $errorMessage');
       }
     } catch (e) {
        // Error de red/inesperado
        print("ConversationApi [createConversation] Excepción: $e"); // Log añadido
        throw Exception('No se pudo conectar al servidor (crear conv): ${e.toString()}');
     }
  }

  /// Obtiene el historial de mensajes para una conversación específica.
  Future<List<dynamic>> getMessages(String token, int conversationId) async {
    print("ConversationApi [getMessages]: Solicitando historial para ID $conversationId...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations/$conversationId/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );
       print("ConversationApi [getMessages]: Respuesta - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final List<dynamic> messages = jsonDecode(response.body);
         print("ConversationApi [getMessages]: ${messages.length} mensajes recibidos.");
        return messages;
      } else {
          // Error de API
          String errorMessage = 'Error desconocido.';
          try {
             final errorBody = jsonDecode(response.body);
             errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
          } catch (_) { errorMessage = response.body; }
           print("ConversationApi [getMessages] Error API: $errorMessage");
          throw Exception('Error al cargar historial: $errorMessage');
      }
    } catch (e) {
       // Error de red/inesperado
       print("ConversationApi [getMessages] Excepción: $e"); // Log añadido
       throw Exception('No se pudo conectar al servidor (historial): ${e.toString()}');
    }
  }
}